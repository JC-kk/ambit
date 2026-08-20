import Foundation

/// Skills are directories containing `SKILL.md`.
///
/// Exposure is a per-skill **symlink** into each agent's discovery directory. Verified against
/// Codex 0.147 (`codex debug prompt-input` finds symlinked skill directories) and against Claude
/// Code 2.1.234, whose skill loader lists entry names without filtering symlinks.
public struct SkillService: Sendable {
    public let env: AmbitEnvironment
    public init(env: AmbitEnvironment) { self.env = env }

    public func exposureDirectory(for agent: AgentKind) -> URL {
        switch agent {
        case .claude: env.claudeSkillsDir
        case .codex: env.codexSkillsDir
        }
    }

    /// Discovery roots we can see but do not control. A skill sitting in one of these is ON for
    /// Codex no matter what we do, so it is reported rather than pretended away.
    var codexUncontrolledRoots: [URL] { [env.sharedAgentsSkillsDir] }

    // MARK: - Scan

    public func scan() -> (capabilities: [Capability], diagnostics: [Diagnostic]) {
        var diagnostics: [Diagnostic] = []

        let libraryNames = Set(FileSafety.directoryEntries(env.librarySkills).filter {
            FileSafety.exists(env.librarySkills.appendingPathComponent($0).appendingPathComponent("SKILL.md"))
        })

        var claudeNames = Set(FileSafety.directoryEntries(env.claudeSkillsDir))
        let codexNames = Set(FileSafety.directoryEntries(env.codexSkillsDir))

        var uncontrolledCodexNames = Set<String>()
        for root in codexUncontrolledRoots where FileSafety.isDirectory(root) {
            uncontrolledCodexNames.formUnion(FileSafety.directoryEntries(root))
        }

        // `~/.claude/skills` being the same directory as a Codex root means Claude exposure
        // implies Codex exposure. Report it; never silently repoint the user's directories.
        let claudeRealPath = FileSafety.realpath(env.claudeSkillsDir)?.path
        let sharedRealPath = FileSafety.realpath(env.sharedAgentsSkillsDir)?.path
        let claudeDirIsCodexRoot = claudeRealPath != nil && claudeRealPath == sharedRealPath
        if claudeDirIsCodexRoot {
            diagnostics.append(Diagnostic(
                id: "skills.claude-dir-is-codex-root",
                severity: .warning,
                message: """
                ~/.claude/skills resolves to ~/.agents/skills, which Codex also scans. \
                Every skill exposed to Claude is therefore forced ON for Codex and its Codex \
                toggle is disabled. To get independent switches, make ~/.claude/skills a real \
                directory again — this app will not change it for you.
                """
            ))
            claudeNames.formUnion(uncontrolledCodexNames)
        }

        let overrides = ClaudeSettings.skillOverrides(env: env)

        var names = libraryNames.union(claudeNames).union(codexNames).union(uncontrolledCodexNames)
        names.remove(".system") // Codex's bundled skills live here and are not ours to manage.

        let capabilities = names.sorted().map { name -> Capability in
            let librarySource = libraryNames.contains(name)
                ? env.librarySkills.appendingPathComponent(name)
                : nil

            let claude = claudeExposure(name: name, librarySource: librarySource, override: overrides[name])
            let codex = codexExposure(
                name: name,
                librarySource: librarySource,
                forcedByUncontrolledRoot: uncontrolledCodexNames.contains(name) && !codexNames.contains(name),
                claudeDirIsCodexRoot: claudeDirIsCodexRoot,
                claudeStatus: claude.status
            )

            let primary = librarySource ?? claude.exposurePath ?? codex.exposurePath
            return Capability(
                kind: .skill,
                name: name,
                summary: summary(name: name, librarySource: librarySource, fallbacks: [claude.exposurePath, codex.exposurePath]),
                librarySource: librarySource,
                primarySource: primary,
                exposures: [.claude: claude, .codex: codex]
            )
        }

        return (capabilities, diagnostics)
    }

    private func summary(name: String, librarySource: URL?, fallbacks: [URL?]) -> String? {
        for candidate in [librarySource] + fallbacks {
            guard let candidate else { continue }
            let skillFile = candidate.appendingPathComponent("SKILL.md")
            guard FileSafety.exists(skillFile) else { continue }
            if let description = Frontmatter.read(skillFile)["description"], !description.isEmpty {
                return description
            }
        }
        return nil
    }

    private func claudeExposure(name: String, librarySource: URL?, override: String?) -> AgentExposure {
        let entry = env.claudeSkillsDir.appendingPathComponent(name)
        let kind = entryKind(entry)

        if override == "off" {
            return AgentExposure(
                status: .off,
                exposurePath: kind == .missing ? nil : entry,
                detail: "Disabled in ~/.claude/settings.json (skillOverrides).",
                canToggle: true
            )
        }

        switch kind {
        case .missing:
            return AgentExposure(
                status: .off,
                detail: librarySource == nil ? "No source in the library to expose." : nil,
                canToggle: librarySource != nil
            )
        case .managedSymlink:
            return AgentExposure(status: .on, exposurePath: entry, canToggle: true)
        case .danglingManagedSymlink:
            return AgentExposure(
                status: .broken, exposurePath: entry,
                detail: "Symlink points into the library but the target is gone.", canToggle: true
            )
        case .foreignSymlink(let target):
            return AgentExposure(
                status: .external, exposurePath: entry,
                detail: "Symlink to \(target), not managed here. Turning it off writes skillOverrides instead of deleting anything.",
                canToggle: true
            )
        case .danglingForeignSymlink:
            return AgentExposure(
                status: .broken, exposurePath: entry,
                detail: "Dangling symlink not created by this app. Remove it yourself.", canToggle: false
            )
        case .realDirectory:
            return AgentExposure(
                status: .external, exposurePath: entry,
                detail: "A real directory in ~/.claude/skills. Turning it off writes skillOverrides; the files are never touched.",
                canToggle: true
            )
        case .invalid:
            return AgentExposure(
                status: .broken, exposurePath: entry,
                detail: "No SKILL.md inside.", canToggle: false
            )
        }
    }

    private func codexExposure(
        name: String,
        librarySource: URL?,
        forcedByUncontrolledRoot: Bool,
        claudeDirIsCodexRoot: Bool,
        claudeStatus: ExposureStatus
    ) -> AgentExposure {
        if forcedByUncontrolledRoot {
            let via = claudeDirIsCodexRoot && claudeStatus != .off ? "~/.claude/skills → ~/.agents/skills" : "~/.agents/skills"
            return AgentExposure(
                status: .external,
                exposurePath: env.sharedAgentsSkillsDir.appendingPathComponent(name),
                detail: "Codex scans \(via), so this is on for Codex regardless of ~/.codex/skills.",
                canToggle: false
            )
        }

        let entry = env.codexSkillsDir.appendingPathComponent(name)
        switch entryKind(entry) {
        case .missing:
            return AgentExposure(
                status: .off,
                detail: librarySource == nil ? "No source in the library to expose." : nil,
                canToggle: librarySource != nil
            )
        case .managedSymlink:
            return AgentExposure(status: .on, exposurePath: entry, canToggle: true)
        case .danglingManagedSymlink:
            return AgentExposure(
                status: .broken, exposurePath: entry,
                detail: "Symlink points into the library but the target is gone.", canToggle: true
            )
        case .foreignSymlink(let target):
            return AgentExposure(
                status: .external, exposurePath: entry,
                detail: "Symlink to \(target), not managed here. Codex has no per-skill off switch, so this cannot be turned off from here.",
                canToggle: false
            )
        case .danglingForeignSymlink:
            return AgentExposure(
                status: .broken, exposurePath: entry,
                detail: "Dangling symlink not created by this app. Remove it yourself.", canToggle: false
            )
        case .realDirectory:
            return AgentExposure(
                status: .external, exposurePath: entry,
                detail: "A real directory in ~/.codex/skills. Codex has no per-skill off switch and this app never deletes real directories — use Adopt first.",
                canToggle: false
            )
        case .invalid:
            return AgentExposure(status: .broken, exposurePath: entry, detail: "No SKILL.md inside.", canToggle: false)
        }
    }

    enum EntryKind: Equatable {
        case missing
        case managedSymlink
        case danglingManagedSymlink
        case foreignSymlink(String)
        case danglingForeignSymlink
        case realDirectory
        case invalid
    }

    func entryKind(_ entry: URL) -> EntryKind {
        guard FileSafety.exists(entry) else { return .missing }
        if FileSafety.isSymlink(entry) {
            let recorded = (try? FileManager.default.destinationOfSymbolicLink(atPath: entry.path)) ?? ""
            let declared = recorded.hasPrefix("/")
                ? URL(fileURLWithPath: recorded)
                : entry.deletingLastPathComponent().appendingPathComponent(recorded)
            let pointsIntoLibrary = declared.standardizedFileURL.path
                .hasPrefix(env.librarySkills.standardizedFileURL.path + "/")

            guard let resolved = FileSafety.realpath(entry) else {
                return pointsIntoLibrary ? .danglingManagedSymlink : .danglingForeignSymlink
            }
            guard FileSafety.exists(resolved.appendingPathComponent("SKILL.md")) else { return .invalid }
            return FileSafety.isContained(resolved, in: env.librarySkills)
                ? .managedSymlink
                : .foreignSymlink(recorded.isEmpty ? resolved.path : recorded)
        }
        guard FileSafety.isDirectory(entry) else { return .invalid }
        return FileSafety.exists(entry.appendingPathComponent("SKILL.md")) ? .realDirectory : .invalid
    }

    // MARK: - Toggle

    public func setEnabled(_ enabled: Bool, name: String, agent: AgentKind) throws {
        enabled ? try enable(name: name, agent: agent) : try disable(name: name, agent: agent)
    }

    private func enable(name: String, agent: AgentKind) throws {
        if agent == .claude, ClaudeSettings.skillOverrides(env: env)[name] == "off" {
            try ClaudeSettings.setSkillOverride(name, to: nil, env: env)
        }

        let entry = exposureDirectory(for: agent).appendingPathComponent(name)
        switch entryKind(entry) {
        case .managedSymlink, .foreignSymlink, .realDirectory:
            return // Already discoverable.
        case .danglingManagedSymlink:
            try FileSafety.removeOwnedSymlink(entry, libraryRoot: env.librarySkills)
        case .danglingForeignSymlink, .invalid:
            throw AmbitError.refused("\(entry.path) exists and was not created by this app. Resolve it by hand first.")
        case .missing:
            break
        }

        let source = env.librarySkills.appendingPathComponent(name)
        guard FileSafety.exists(source.appendingPathComponent("SKILL.md")) else {
            throw AmbitError.refused("No library skill named \"\(name)\" to expose. Use Adopt first.")
        }
        try FileSafety.createSymlink(at: entry, target: source)
    }

    private func disable(name: String, agent: AgentKind) throws {
        let entry = exposureDirectory(for: agent).appendingPathComponent(name)
        switch entryKind(entry) {
        case .managedSymlink, .danglingManagedSymlink:
            try FileSafety.removeOwnedSymlink(entry, libraryRoot: env.librarySkills)
        case .missing:
            if agent == .claude { try ClaudeSettings.setSkillOverride(name, to: "off", env: env) }
        case .foreignSymlink, .realDirectory:
            guard agent == .claude else {
                throw AmbitError.refused("""
                \"\(name)\" is not managed by this app and Codex has no per-skill off switch. \
                Use Adopt to move it into the library first, or remove it from ~/.codex/skills yourself.
                """)
            }
            // Non-destructive: Claude's own setting hides it, the files stay put.
            try ClaudeSettings.setSkillOverride(name, to: "off", env: env)
        case .danglingForeignSymlink, .invalid:
            throw AmbitError.refused("\(entry.path) is in an unexpected state and was not created by this app. Resolve it by hand.")
        }
    }

    // MARK: - Adopt

    /// Copies an external skill into the library, parks the original under `backups/`, and
    /// replaces it with a managed symlink. Never runs without an explicit user action.
    public func adopt(name: String, from agent: AgentKind) throws {
        let entry = exposureDirectory(for: agent).appendingPathComponent(name)
        guard case .realDirectory = entryKind(entry) else {
            throw AmbitError.refused("\(entry.path) is not a real skill directory; there is nothing to adopt.")
        }
        let destination = env.librarySkills.appendingPathComponent(name)
        guard !FileSafety.exists(destination) else {
            throw AmbitError.refused("The library already has a skill named \"\(name)\".")
        }

        try FileSafety.ensureDirectory(env.librarySkills)
        try FileManager.default.copyItem(at: entry, to: destination)
        guard FileSafety.exists(destination.appendingPathComponent("SKILL.md")) else {
            try? FileManager.default.removeItem(at: destination)
            throw AmbitError.io("The copy into the library came out incomplete; nothing was changed.")
        }

        // The original is parked, not deleted, so an adopt is always undoable.
        let parked = env.libraryBackups
            .appendingPathComponent("adopted-\(DateFormatter.ambitStamp.string(from: Date()))")
            .appendingPathComponent(name)
        try FileSafety.ensureDirectory(parked.deletingLastPathComponent())
        try FileManager.default.moveItem(at: entry, to: parked)

        do {
            try FileSafety.createSymlink(at: entry, target: destination)
        } catch {
            try? FileManager.default.moveItem(at: parked, to: entry) // Put it back exactly as it was.
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}
