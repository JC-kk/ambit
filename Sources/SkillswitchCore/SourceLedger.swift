import Foundation

/// A tombstone ledger of capabilities this app has taken responsibility for.
///
/// Status is otherwise always derived from the filesystem, deliberately, so it cannot drift. But
/// pure derivation has one blind spot: a library source that gets deleted by something else simply
/// stops appearing, and a manager whose pitch is "nothing is deleted" must not lose a source in
/// silence. This records **names only** — never enabled state — so there is nothing to go stale.
/// A name is remembered once a library copy exists for it, and reported if that copy later vanishes.
public struct SourceLedger: Sendable {
    public let env: SkillswitchEnvironment
    public init(env: SkillswitchEnvironment) { self.env = env }

    var file: URL { env.library.appendingPathComponent("index.json") }

    public struct Snapshot: Sendable {
        public var known: [CapabilityKind: Set<String>] = [:]
    }

    public func load() -> Snapshot {
        var snapshot = Snapshot()
        guard let object = try? JSONConfig.read(file),
              let known = object["known"] as? [String: Any] else { return snapshot }
        for kind in CapabilityKind.allCases {
            let names = (known[kind.rawValue] as? [Any])?.compactMap { $0 as? String } ?? []
            snapshot.known[kind] = Set(names)
        }
        return snapshot
    }

    /// Names that were managed here and whose source is now gone.
    public func missing(present: [CapabilityKind: Set<String>]) -> [CapabilityKind: [String]] {
        let known = load().known
        var result: [CapabilityKind: [String]] = [:]
        for kind in CapabilityKind.allCases {
            let gone = (known[kind] ?? []).subtracting(present[kind] ?? [])
            if !gone.isEmpty { result[kind] = gone.sorted() }
        }
        return result
    }

    /// Adds anything newly managed. Never removes — that is `forget`'s job, so a vanished source
    /// keeps being reported until the user acknowledges it or puts it back.
    public func remember(_ present: [CapabilityKind: Set<String>]) {
        var known = load().known
        var changed = false
        for kind in CapabilityKind.allCases {
            let merged = (known[kind] ?? []).union(present[kind] ?? [])
            if merged != (known[kind] ?? []) { changed = true }
            known[kind] = merged
        }
        guard changed else { return }
        write(known)
    }

    public func forget(_ names: [CapabilityKind: [String]]) {
        var known = load().known
        for (kind, list) in names {
            known[kind] = (known[kind] ?? []).subtracting(list)
        }
        write(known)
    }

    private func write(_ known: [CapabilityKind: Set<String>]) {
        var payload: [String: Any] = [:]
        for kind in CapabilityKind.allCases where !(known[kind] ?? []).isEmpty {
            payload[kind.rawValue] = (known[kind] ?? []).sorted()
        }
        let object: [String: Any] = ["version": 1, "known": payload]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        ) else { return }
        try? FileSafety.ensureDirectory(env.library)
        try? FileSafety.atomicWrite(data, to: file)
    }
}
