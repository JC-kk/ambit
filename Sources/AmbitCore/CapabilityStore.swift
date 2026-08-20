import Foundation

/// The single entry point the UI talks to: scan everything, toggle one thing, adopt one thing.
public struct CapabilityStore: Sendable {
    public let env: AmbitEnvironment
    public let skills: SkillService
    public let subagents: SubagentService
    public let mcp: MCPService
    public let consolidation: ConsolidationService
    public let ledger: SourceLedger

    public init(env: AmbitEnvironment = .live) {
        self.env = env
        skills = SkillService(env: env)
        subagents = SubagentService(env: env)
        mcp = MCPService(env: env)
        consolidation = ConsolidationService(env: env)
        ledger = SourceLedger(env: env)
    }

    /// Creates the library directories. Touches nothing that belongs to Claude or Codex.
    public func prepareLibrary() throws {
        for directory in [env.librarySkills, env.libraryClaudeAgents, env.libraryCodexAgents, env.libraryParkedClaudeMCP] {
            try FileSafety.ensureDirectory(directory)
        }
    }

    public func scan() -> Inventory {
        let s = skills.scan()
        let m = mcp.scan()
        let a = subagents.scan()
        let capabilities = s.capabilities + m.capabilities + a.capabilities
        var diagnostics = s.diagnostics + m.diagnostics + a.diagnostics

        // Only library-backed capabilities are remembered: those are the ones this app took
        // responsibility for. An external capability the user removes from their own directory is
        // their business, not a loss we should nag about.
        let missing = ledger.missing(present: presentNames(in: capabilities))
        ledger.remember(managedNames(in: capabilities))

        if !missing.isEmpty {
            diagnostics.append(Diagnostic(
                id: "library.source-missing",
                severity: .warning,
                message: Self.missingMessage(missing)
            ))
        }
        return Inventory(capabilities: capabilities, diagnostics: diagnostics)
    }

    /// Stops reporting sources that have gone missing.
    public func forgetMissingSources() {
        let present = presentNames(in: scan().capabilities)
        ledger.forget(ledger.missing(present: present))
    }

    /// What to start remembering: a library copy exists, so this app is now holding the source.
    private func managedNames(in capabilities: [Capability]) -> [CapabilityKind: Set<String>] {
        var managed: [CapabilityKind: Set<String>] = [:]
        for capability in capabilities where capability.librarySource != nil {
            managed[capability.kind, default: []].insert(capability.name)
        }
        return managed
    }

    /// What still exists — deliberately wider than `managedNames`, because for MCP a library copy
    /// is only *one* of the places a definition legitimately lives. Parking is a move: enabling a
    /// parked server for Claude puts its JSON back into ~/.claude.json and drops the library copy,
    /// so judging presence by the library alone would report an ordinary toggle as a lost source.
    /// An MCP name reaches the inventory only from the parked directory, ~/.claude.json or
    /// config.toml, so appearing here is itself proof the definition survives somewhere.
    private func presentNames(in capabilities: [Capability]) -> [CapabilityKind: Set<String>] {
        var present: [CapabilityKind: Set<String>] = [:]
        for capability in capabilities where capability.kind == .mcp || capability.librarySource != nil {
            present[capability.kind, default: []].insert(capability.name)
        }
        return present
    }

    static func missingMessage(_ missing: [CapabilityKind: [String]]) -> String {
        let summary = CapabilityKind.allCases.compactMap { kind -> String? in
            guard let names = missing[kind], !names.isEmpty else { return nil }
            return kind.displayName.lowercased() + ": " + names.joined(separator: ", ")
        }.joined(separator: "; ")
        return "A source this app was managing is no longer in the library — " + summary
            + ". Nothing here deletes library sources, so something else removed it"
            + " (a skill uninstall that followed the symlink, or a manual delete)."
            + " Restore it from a backup, or dismiss to stop tracking it."
    }

    public func setEnabled(_ enabled: Bool, capability: Capability, agent: AgentKind) throws {
        let exposure = capability.exposure(agent)
        guard exposure.canToggle else {
            throw AmbitError.refused(exposure.detail ?? "\(capability.name) cannot be toggled for \(agent.displayName).")
        }
        switch capability.kind {
        case .skill: try skills.setEnabled(enabled, name: capability.name, agent: agent)
        case .mcp: try mcp.setEnabled(enabled, name: capability.name, agent: agent)
        case .subagent: try subagents.setEnabled(enabled, name: capability.name, agent: agent)
        }
    }

    /// Applies one state to many capabilities, doing as much as it legitimately can.
    ///
    /// Returns the refusals in order rather than throwing on the first one: any real column is a
    /// mix of rows we govern and rows we do not, and abandoning the batch at the first `N/A` would
    /// leave the user worse off than not offering it. Already-correct rows are skipped, so nothing
    /// is rewritten just to arrive at the state it was already in.
    ///
    /// `reportingSkips` is the difference between a master switch and a batch over hand-picked
    /// rows. A master switch stands for a column the user never enumerated, so rows it cannot move
    /// are simply not its business; an explicit selection is, and being told "these three were left
    /// alone" is the whole point there.
    @discardableResult
    public func setAll(
        _ enabled: Bool,
        capabilities: [Capability],
        agent: AgentKind,
        reportingSkips: Bool = false
    ) -> [String] {
        var failures: [String] = []
        for capability in capabilities {
            let exposure = capability.exposure(agent)
            guard exposure.canToggle else {
                if reportingSkips {
                    failures.append("\(capability.name): \(exposure.detail ?? "cannot be toggled")")
                }
                continue
            }
            guard (exposure.status == .on) != enabled else { continue }
            do {
                try setEnabled(enabled, capability: capability, agent: agent)
            } catch {
                failures.append("\(capability.name): \(error.localizedDescription)")
            }
        }
        return failures
    }

    public func canAdopt(_ capability: Capability) -> Bool {
        guard capability.librarySource == nil else { return false }
        switch capability.kind {
        case .skill:
            return AgentKind.allCases.contains { capability.exposure($0).status == .external }
        case .subagent:
            return capability.exposure(.claude).status == .external
        case .mcp:
            return false // MCP definitions already live in the agents' own configs.
        }
    }

    public func adopt(_ capability: Capability) throws {
        switch capability.kind {
        case .skill:
            guard let agent = AgentKind.allCases.first(where: { capability.exposure($0).status == .external }) else {
                throw AmbitError.refused("\(capability.name) has no external directory to adopt.")
            }
            try skills.adopt(name: capability.name, from: agent)
        case .subagent:
            try subagents.adopt(name: capability.name)
        case .mcp:
            throw AmbitError.refused("MCP servers are managed in place; there is nothing to adopt.")
        }
    }
}
