import Foundation

/// Filesystem primitives with the safety rules of this app baked in.
///
/// Nothing here deletes a regular file or a directory. The only removals available are
/// `removeOwnedSymlink` and `removeOwnedHardLink`, both of which demand proof of ownership.
public enum FileSafety {

    // MARK: - Inspection

    public static func lstat(_ url: URL) -> stat? {
        var st = stat()
        guard Foundation.lstat(url.path, &st) == 0 else { return nil }
        return st
    }

    public static func exists(_ url: URL) -> Bool { lstat(url) != nil }

    public static func isSymlink(_ url: URL) -> Bool {
        guard let st = lstat(url) else { return false }
        return (st.st_mode & S_IFMT) == S_IFLNK
    }

    public static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        return isDir.boolValue
    }

    /// Follows symlinks, so a hard link and a symlink-to-a-file both answer true.
    public static func isRegularFile(_ url: URL) -> Bool {
        guard let resolved = realpath(url), let st = lstat(resolved) else { return false }
        return (st.st_mode & S_IFMT) == S_IFREG
    }

    /// Fully resolved path, or nil when the link dangles.
    public static func realpath(_ url: URL) -> URL? {
        guard let cstr = Foundation.realpath(url.path, nil) else { return nil }
        defer { free(cstr) }
        return URL(fileURLWithPath: String(cString: cstr))
    }

    /// Resolves symlinks in the *parent* chain so containment checks are not fooled by
    /// `~/.claude/skills` itself being a symlink.
    public static func canonicalPrefix(_ url: URL) -> String {
        (realpath(url) ?? url.standardizedFileURL).path
    }

    public static func isContained(_ url: URL, in directory: URL) -> Bool {
        let dir = canonicalPrefix(directory)
        let target = (realpath(url) ?? url.standardizedFileURL).path
        return target == dir || target.hasPrefix(dir.hasSuffix("/") ? dir : dir + "/")
    }

    /// Two paths refer to the same inode — the ownership proof used for hard links.
    public static func sameInode(_ a: URL, _ b: URL) -> Bool {
        guard let sa = lstat(a), let sb = lstat(b) else { return false }
        return sa.st_dev == sb.st_dev && sa.st_ino == sb.st_ino
    }

    public static func linkCount(_ url: URL) -> Int {
        Int(lstat(url)?.st_nlink ?? 0)
    }

    public static func directoryEntries(_ url: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path))?
            .filter { !$0.hasPrefix(".") }
            .sorted() ?? []
    }

    // MARK: - Creation

    public static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Creates `link` -> `target`. Refuses to clobber anything that already exists.
    public static func createSymlink(at link: URL, target: URL) throws {
        guard !exists(link) else {
            throw SkillswitchError.refused("\(link.path) already exists; refusing to replace it.")
        }
        try ensureDirectory(link.deletingLastPathComponent())
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
    }

    /// Creates a hard link. Refuses to clobber anything that already exists.
    public static func createHardLink(at link: URL, target: URL) throws {
        guard !exists(link) else {
            throw SkillswitchError.refused("\(link.path) already exists; refusing to replace it.")
        }
        guard isRegularFile(target) else {
            throw SkillswitchError.refused("\(target.path) is not a regular file; cannot hard link it.")
        }
        try ensureDirectory(link.deletingLastPathComponent())
        guard Foundation.link(target.path, link.path) == 0 else {
            throw SkillswitchError.io("Could not hard link \(link.path): \(String(cString: strerror(errno))).")
        }
    }

    // MARK: - Guarded removal

    /// Removes `link` only if it is a symlink resolving inside `libraryRoot`.
    public static func removeOwnedSymlink(_ link: URL, libraryRoot: URL) throws {
        guard isSymlink(link) else {
            throw SkillswitchError.refused("\(link.path) is not a symlink. This app only removes links it created.")
        }
        guard let resolved = realpath(link) else {
            // A dangling link is only ours if its recorded destination points into the library.
            let dest = (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) ?? ""
            let absolute = dest.hasPrefix("/")
                ? URL(fileURLWithPath: dest)
                : link.deletingLastPathComponent().appendingPathComponent(dest)
            guard absolute.standardizedFileURL.path.hasPrefix(libraryRoot.standardizedFileURL.path + "/") else {
                throw SkillswitchError.refused("\(link.path) is a dangling symlink that does not point into the library. Leaving it alone.")
            }
            try FileManager.default.removeItem(at: link)
            return
        }
        guard isContained(resolved, in: libraryRoot) else {
            throw SkillswitchError.refused("\(link.path) points outside the library (\(resolved.path)). Refusing to remove it.")
        }
        try FileManager.default.removeItem(at: link)
    }

    /// Removes `link` only if it shares an inode with `librarySource` — proving we made it and
    /// proving the library copy survives the unlink.
    public static func removeOwnedHardLink(_ link: URL, librarySource: URL) throws {
        guard isSymlink(link) == false else {
            throw SkillswitchError.refused("\(link.path) is a symlink, not a hard link this app created.")
        }
        guard sameInode(link, librarySource) else {
            throw SkillswitchError.refused("\(link.path) is a separate file, not a hard link to the library copy. Refusing to delete it.")
        }
        guard linkCount(link) >= 2 else {
            throw SkillswitchError.refused("\(link.path) is the only remaining link to its data. Refusing to delete it.")
        }
        try FileManager.default.removeItem(at: link)
    }

    // MARK: - Backup + atomic write

    /// Copies `url` into `<library>/backups/<timestamp>/` before it is modified.
    @discardableResult
    public static func backup(_ url: URL, env: SkillswitchEnvironment) throws -> URL? {
        guard exists(url) else { return nil }
        let stamp = DateFormatter.skillswitchStamp.string(from: Date())
        let dir = env.libraryBackups.appendingPathComponent(stamp)
        try ensureDirectory(dir)
        // Flatten the path so two backups in one run cannot collide.
        let flat = url.path
            .replacingOccurrences(of: env.home.path, with: "~")
            .replacingOccurrences(of: "/", with: "%")
        let dest = dir.appendingPathComponent(flat)
        if exists(dest) { try FileManager.default.removeItem(at: dest) }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    /// Writes via a temp file in the same directory then `rename(2)`, so a reader never sees a
    /// half-written config and a crash cannot truncate the original. Preserves the existing mode.
    public static func atomicWrite(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try ensureDirectory(dir)
        let mode = lstat(url).map { $0.st_mode & 0o7777 }
        let temp = dir.appendingPathComponent(".skillswitch-\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if let mode {
                try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: temp.path)
            }
            guard Foundation.rename(temp.path, url.path) == 0 else {
                throw SkillswitchError.io("Could not replace \(url.path): \(String(cString: strerror(errno))).")
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }
}

extension DateFormatter {
    /// Colon-free so the stamp is a legal, Finder-friendly directory name.
    static let skillswitchStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
