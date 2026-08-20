import Foundation

/// The single entry point the UI talks to: scan everything, toggle one thing, adopt one thing.
public struct CapabilityStore: Sendable {
    public let env: ACMEnvironment
    public let skills: SkillService
    public let subagents: SubagentService
    public let mcp: MCPService
    public let consolidation: ConsolidationService
    public let ledger: SourceLedger

    public init(env: ACMEnvironment = .live) {
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
        let managed = managedNames(in: capabilities)
        let missing = ledger.missing(present: managed)
        ledger.remember(managed)

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
        let managed = managedNames(in: scan().capabilities)
        ledger.forget(ledger.missing(present: managed))
    }

    private func managedNames(in capabilities: [Capability]) -> [CapabilityKind: Set<String>] {
        var managed: [CapabilityKind: Set<String>] = [:]
        for capability in capabilities where capability.librarySource != nil {
            managed[capability.kind, default: []].insert(capability.name)
        }
        return managed
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
            throw ACMError.refused(exposure.detail ?? "\(capability.name) cannot be toggled for \(agent.displayName).")
        }
        switch capability.kind {
        case .skill: try skills.setEnabled(enabled, name: capability.name, agent: agent)
        case .mcp: try mcp.setEnabled(enabled, name: capability.name, agent: agent)
        case .subagent: try subagents.setEnabled(enabled, name: capability.name, agent: agent)
        }
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
                throw ACMError.refused("\(capability.name) has no external directory to adopt.")
            }
            try skills.adopt(name: capability.name, from: agent)
        case .subagent:
            try subagents.adopt(name: capability.name)
        case .mcp:
            throw ACMError.refused("MCP servers are managed in place; there is nothing to adopt.")
        }
    }
}
