import Foundation

/// Read / minimally-modify / validate / atomically-write for the JSON configs Claude Code owns.
///
/// The edit itself is a text splice (see `JSONTextEditor`), so unknown keys survive literally —
/// same bytes, same order, same number formatting. The validation below then re-parses the result
/// and proves that nothing outside the intended key moved.
public enum JSONConfig {

    public static func read(_ url: URL) throws -> [String: Any] {
        guard FileSafety.exists(url) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AmbitError.parse("\(url.lastPathComponent) is not a JSON object.")
        }
        return object
    }

    /// Sets one top-level key, or removes it when `value` is nil.
    public static func setTopLevelValue(
        _ value: Any?,
        forKey key: String,
        in url: URL,
        env: AmbitEnvironment
    ) throws {
        let original = FileSafety.exists(url) ? (try String(contentsOf: url, encoding: .utf8)) : ""
        let before = try read(url)

        let updated = try JSONTextEditor.setTopLevelValue(value, forKey: key, in: original)
        guard updated != original else { return }

        // Validate before touching the real file: it must still parse, the edited key must hold
        // exactly what we asked for, and every other key must be untouched.
        guard let data = updated.data(using: .utf8),
              let after = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AmbitError.parse("The edit did not produce valid JSON; \(url.lastPathComponent) was left alone.")
        }
        guard deepEqual(after[key], value) else {
            throw AmbitError.parse("The edit to \"\(key)\" did not take effect as expected; \(url.lastPathComponent) was left alone.")
        }
        for other in Set(before.keys).union(after.keys) where other != key {
            guard deepEqual(before[other], after[other]) else {
                throw AmbitError.refused("Refusing to write \(url.lastPathComponent): the edit would also change \"\(other)\".")
            }
        }

        try FileSafety.backup(url, env: env)
        try FileSafety.atomicWrite(data, to: url)
    }

    public static func deepEqual(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        default: break
        }
        if let x = a as? [String: Any], let y = b as? [String: Any] {
            guard Set(x.keys) == Set(y.keys) else { return false }
            return x.keys.allSatisfy { deepEqual(x[$0], y[$0]) }
        }
        if let x = a as? [Any], let y = b as? [Any] {
            guard x.count == y.count else { return false }
            return zip(x, y).allSatisfy { deepEqual($0, $1) }
        }
        if let x = a as? NSNumber, let y = b as? NSNumber { return x == y }
        if let x = a as? String, let y = b as? String { return x == y }
        if a is NSNull && b is NSNull { return true }
        return false
    }
}
