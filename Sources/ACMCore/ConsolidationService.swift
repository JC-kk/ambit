import Foundation

/// Moves the real skill directories and subagent files that currently live inside Claude's and
/// Codex's own folders into the library, then links them back so nothing changes about what each
/// agent can see. After this, the library holds the only copy of every source and the per-agent
/// switches are genuinely independent.
///
/// Everything is planned first and shown to the user. Nothing is deleted: a duplicate that cannot
/// become the canonical copy is parked under `backups/`, and a manifest of every move is written
/// so the whole operation can be walked back by hand.
public struct ConsolidationService: Sendable {
    public let env: ACMEnvironment
    public init(env: ACMEnvironment) { self.env = env }

    // MARK: - Plan

    public struct Move: Sendable, Identifiable, Codable {
        public var kind: CapabilityKind
        public var name: String
        /// The real directory or file that becomes the library copy.
        public var source: URL
        /// Duplicates of the same name that will be parked rather than used.
        public var parked: [URL]
        /// Agents that can see it today and must still see it afterwards.
        public var relinkTo: [AgentKind]
        public var id: String { "\(kind.rawValue):\(name)" }

        public init(kind: CapabilityKind, name: String, source: URL, parked: [URL], relinkTo: [AgentKind]) {
            self.kind = kind
            self.name = name
            self.source = source
            self.parked = parked
            self.relinkTo = relinkTo
        }
    }

    public struct Plan: Sendable, Codable {
        public var moves: [Move] = []
        public var blocked: [String] = []
        /// True when `~/.claude/skills` is a symlink that has to become a real directory before
        /// Claude and Codex can be switched independently.
        public var replacesClaudeSkillsSymlink = false
        public var claudeSkillsSymlinkTarget: URL?

        public init() {}

        public var isEmpty: Bool { moves.isEmpty && !replacesClaudeSkillsSymlink }
        public func moves(_ kind: CapabilityKind) -> [Move] { moves.filter { $0.kind == kind } }
    }

    public func plan() -> Plan {
        var plan = Plan()

        let claudeSkillsIsSymlink = FileSafety.isSymlink(env.claudeSkillsDir)
        if claudeSkillsIsSymlink {
            plan.replacesClaudeSkillsSymlink = true
            plan.claudeSkillsSymlinkTarget = FileSafety.realpath(env.claudeSkillsDir)
        }

        // Roots that can hold a real skill directory today, in the order we prefer to take the
        // canonical copy from.
        let skillRoots: [(URL, [AgentKind])] = [
            (env.sharedAgentsSkillsDir, claudeSkillsIsSymlink ? [.claude, .codex] : [.codex]),
            (env.claudeSkillsDir, [.claude]),
            (env.codexSkillsDir, [.codex]),
        ]

        var seenRealPaths = Set<String>()
        var candidates: [String: (source: URL, duplicates: [URL], agents: Set<AgentKind>)] = [:]

        for (root, agents) in skillRoots {
            guard FileSafety.isDirectory(root) else { continue }
            for name in FileSafety.directoryEntries(root) {
                let entry = root.appendingPathComponent(name)
                guard FileSafety.isDirectory(entry), !FileSafety.isSymlink(entry),
                      FileSafety.exists(entry.appendingPathComponent("SKILL.md")) else { continue }

                // `~/.claude/skills` aliased onto `~/.agents/skills` lists the same inode twice.
                let real = FileSafety.canonicalPrefix(entry)
                if seenRealPaths.contains(real) {
                    candidates[name]?.agents.formUnion(agents)
                    continue
                }
                seenRealPaths.insert(real)

                if var existing = candidates[name] {
                    existing.duplicates.append(entry)
                    existing.agents.formUnion(agents)
                    candidates[name] = existing
                } else {
                    candidates[name] = (source: entry, duplicates: [], agents: Set(agents))
                }
            }
        }

        for (name, candidate) in candidates.sorted(by: { $0.key < $1.key }) {
            guard !FileSafety.exists(env.librarySkills.appendingPathComponent(name)) else {
                plan.blocked.append("Skill “\(name)”: the library already has one. Leaving \(candidate.source.path.abbreviatingHome) where it is.")
                continue
            }
            plan.moves.append(Move(
                kind: .skill, name: name, source: candidate.source,
                parked: candidate.duplicates,
                relinkTo: AgentKind.allCases.filter { candidate.agents.contains($0) }
            ))
        }

        // Subagents: any real .md in ~/.claude/agents that is not already the library file.
        for entry in FileSafety.directoryEntries(env.claudeAgentsDir) where entry.hasSuffix(".md") {
            let file = env.claudeAgentsDir.appendingPathComponent(entry)
            guard FileSafety.isRegularFile(file), !FileSafety.isSymlink(file) else { continue }
            let name = (entry as NSString).deletingPathExtension
            let library = env.libraryClaudeAgents.appendingPathComponent(entry)
            if FileSafety.exists(library) {
                if !FileSafety.sameInode(file, library) {
                    plan.blocked.append("Subagent “\(name)”: the library already has a different file with that name.")
                }
                continue
            }
            plan.moves.append(Move(kind: .subagent, name: name, source: file, parked: [], relinkTo: [.claude]))
        }

        plan.moves.sort { ($0.kind.rawValue, $0.name) < ($1.kind.rawValue, $1.name) }
        return plan
    }

    // MARK: - Apply

    @discardableResult
    public func apply(_ plan: Plan) throws -> URL {
        try FileSafety.ensureDirectory(env.librarySkills)
        try FileSafety.ensureDirectory(env.libraryClaudeAgents)

        let stamp = DateFormatter.acmStamp.string(from: Date())
        let record = env.libraryBackups.appendingPathComponent("consolidate-\(stamp)")
        try FileSafety.ensureDirectory(record)

        var log: [[String: String]] = []

        // 1. Move every canonical source into the library. Duplicates are parked, never deleted.
        for move in plan.moves {
            let destination = move.kind == .skill
                ? env.librarySkills.appendingPathComponent(move.name)
                : env.libraryClaudeAgents.appendingPathComponent("\(move.name).md")

            guard !FileSafety.exists(destination) else {
                throw ACMError.refused("\(destination.path) appeared while consolidating; stopping before anything else moves.")
            }
            try FileManager.default.moveItem(at: move.source, to: destination)
            log.append(["action": "move", "from": move.source.path, "to": destination.path])

            for duplicate in move.parked {
                let parked = record.appendingPathComponent("duplicate-\(move.name)-\(UUID().uuidString.prefix(6))")
                try FileManager.default.moveItem(at: duplicate, to: parked)
                log.append(["action": "park-duplicate", "from": duplicate.path, "to": parked.path])
            }
        }

        // 2. Turn ~/.claude/skills from a symlink into a real directory, so a link placed there is
        //    no longer also visible through the Codex-scanned ~/.agents/skills.
        if plan.replacesClaudeSkillsSymlink, FileSafety.isSymlink(env.claudeSkillsDir) {
            let target = FileSafety.realpath(env.claudeSkillsDir)
            try FileManager.default.removeItem(at: env.claudeSkillsDir)
            try FileSafety.ensureDirectory(env.claudeSkillsDir)
            log.append([
                "action": "replace-symlink-with-directory",
                "path": env.claudeSkillsDir.path,
                "previousTarget": target?.path ?? "",
            ])
        }

        // 3. Link everything back so each agent sees exactly what it saw a moment ago.
        for move in plan.moves {
            for agent in move.relinkTo {
                switch move.kind {
                case .skill:
                    let link = (agent == .claude ? env.claudeSkillsDir : env.codexSkillsDir)
                        .appendingPathComponent(move.name)
                    guard !FileSafety.exists(link) else { continue }
                    try FileSafety.createSymlink(at: link, target: env.librarySkills.appendingPathComponent(move.name))
                    log.append(["action": "symlink", "at": link.path])
                case .subagent:
                    let link = env.claudeAgentsDir.appendingPathComponent("\(move.name).md")
                    guard !FileSafety.exists(link) else { continue }
                    try FileSafety.createHardLink(at: link, target: env.libraryClaudeAgents.appendingPathComponent("\(move.name).md"))
                    log.append(["action": "hardlink", "at": link.path])
                case .mcp:
                    continue
                }
            }
        }

        let manifest = record.appendingPathComponent("manifest.json")
        let data = try JSONSerialization.data(
            withJSONObject: ["performedAt": stamp, "steps": log],
            options: [.prettyPrinted, .withoutEscapingSlashes]
        )
        try FileSafety.atomicWrite(data, to: manifest)
        return manifest
    }
}

extension String {
    var abbreviatingHome: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
