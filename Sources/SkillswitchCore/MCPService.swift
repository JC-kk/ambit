import Foundation

/// One transport-neutral description of an MCP server, used to translate a definition between
/// Claude Code's JSON and Codex's TOML. Round-tripping a server through its *own* agent never
/// goes through this type — that path preserves the original object verbatim.
public struct MCPDefinition: Sendable, Equatable {
    public enum Transport: String, Sendable { case stdio, http, sse }

    public var name: String
    public var transport: Transport
    public var command: String?
    public var args: [String]
    public var environment: [String: String]
    public var url: String?

    public init(
        name: String,
        transport: Transport,
        command: String? = nil,
        args: [String] = [],
        environment: [String: String] = [:],
        url: String? = nil
    ) {
        self.name = name
        self.transport = transport
        self.command = command
        self.args = args
        self.environment = environment
        self.url = url
    }

    public var oneLineSummary: String {
        switch transport {
        case .stdio: ([command] + args).compactMap { $0 }.joined(separator: " ")
        case .http, .sse: url ?? ""
        }
    }
}

/// MCP is the one capability that is *not* a symlink problem.
///
/// * **Codex** has a native per-server switch: `enabled = false` under `[mcp_servers.<name>]`.
///   Disabling flips exactly that one key and leaves the rest of `config.toml` byte-identical.
/// * **Claude Code** has no global per-server switch — the `disabledMcpServers` setting is keyed
///   per project inside `~/.claude.json → projects[cwd]`. So a disabled server is *parked*: its
///   JSON object is moved verbatim into the library and moved back on enable.
public struct MCPService: Sendable {
    public let env: SkillswitchEnvironment
    public init(env: SkillswitchEnvironment) { self.env = env }

    static let codexTableRoot = "mcp_servers"

    // MARK: - Scan

    public func scan() -> (capabilities: [Capability], diagnostics: [Diagnostic]) {
        var diagnostics: [Diagnostic] = []

        let claudeActive = claudeServers()
        let parked = parkedServers()

        var codexActive: [String: [String: TOML.Value]] = [:]
        var codexParseFailed = false
        if FileSafety.exists(env.codexConfigTOML) {
            do {
                let text = try String(contentsOf: env.codexConfigTOML, encoding: .utf8)
                let root = try TOML.parse(text)
                if let servers = TOML.table(root, at: [Self.codexTableRoot]) {
                    for (name, value) in servers {
                        if let table = value.tableValue { codexActive[name] = table }
                    }
                }
            } catch {
                codexParseFailed = true
                diagnostics.append(Diagnostic(
                    id: "mcp.codex-config-unparsed",
                    severity: .warning,
                    message: "Could not parse ~/.codex/config.toml (\(error.localizedDescription)). Codex MCP toggles are disabled until it parses cleanly."
                ))
            }
        }

        let names = Set(claudeActive.keys).union(parked.keys).union(codexActive.keys).sorted()

        let capabilities = names.map { name -> Capability in
            let claude = claudeExposure(name: name, active: claudeActive, parked: parked, codexHasIt: codexActive[name] != nil)
            let codex = codexExposure(
                name: name,
                table: codexActive[name],
                parseFailed: codexParseFailed,
                claudeHasIt: claudeActive[name] != nil || parked[name] != nil
            )

            let definition = definitionFor(name: name, claudeActive: claudeActive, parked: parked, codexTable: codexActive[name])
            return Capability(
                kind: .mcp,
                name: name,
                summary: definition.map { "\($0.transport.rawValue) · \($0.oneLineSummary)" },
                librarySource: parked[name] != nil ? parkedFile(name) : nil,
                primarySource: claudeActive[name] != nil ? env.claudeJSON
                    : (codexActive[name] != nil ? env.codexConfigTOML : parkedFile(name)),
                exposures: [.claude: claude, .codex: codex]
            )
        }
        return (capabilities, diagnostics)
    }

    private func claudeExposure(
        name: String,
        active: [String: [String: Any]],
        parked: [String: [String: Any]],
        codexHasIt: Bool
    ) -> AgentExposure {
        if active[name] != nil {
            return AgentExposure(status: .on, exposurePath: env.claudeJSON, canToggle: true)
        }
        if parked[name] != nil {
            return AgentExposure(
                status: .off, exposurePath: parkedFile(name),
                detail: "Parked in the library. The full definition is kept verbatim and restored on enable.",
                canToggle: true
            )
        }
        return AgentExposure(
            status: .off,
            detail: codexHasIt ? "Defined for Codex only. Turning this on writes a converted entry into ~/.claude.json." : nil,
            canToggle: codexHasIt
        )
    }

    private func codexExposure(
        name: String,
        table: [String: TOML.Value]?,
        parseFailed: Bool,
        claudeHasIt: Bool
    ) -> AgentExposure {
        if parseFailed {
            return AgentExposure(status: .broken, exposurePath: env.codexConfigTOML,
                                 detail: "~/.codex/config.toml could not be parsed.", canToggle: false)
        }
        guard let table else {
            return AgentExposure(
                status: .off,
                detail: claudeHasIt ? "Defined for Claude only. Turning this on appends a converted [mcp_servers] table to ~/.codex/config.toml." : nil,
                canToggle: claudeHasIt
            )
        }
        if table["enabled"]?.boolValue == false {
            return AgentExposure(
                status: .off, exposurePath: env.codexConfigTOML,
                detail: "enabled = false in [mcp_servers.\(name)].", canToggle: true
            )
        }
        return AgentExposure(status: .on, exposurePath: env.codexConfigTOML, canToggle: true)
    }

    // MARK: - Reading

    func claudeServers() -> [String: [String: Any]] {
        let root = (try? JSONConfig.read(env.claudeJSON)) ?? [:]
        guard let servers = root["mcpServers"] as? [String: Any] else { return [:] }
        return servers.compactMapValues { $0 as? [String: Any] }
    }

    func parkedFile(_ name: String) -> URL {
        env.libraryParkedClaudeMCP.appendingPathComponent("\(name).json")
    }

    func parkedServers() -> [String: [String: Any]] {
        var out: [String: [String: Any]] = [:]
        for entry in FileSafety.directoryEntries(env.libraryParkedClaudeMCP) where entry.hasSuffix(".json") {
            let name = (entry as NSString).deletingPathExtension
            let url = env.libraryParkedClaudeMCP.appendingPathComponent(entry)
            if let object = try? JSONConfig.read(url) { out[name] = object }
        }
        return out
    }

    func definitionFor(
        name: String,
        claudeActive: [String: [String: Any]],
        parked: [String: [String: Any]],
        codexTable: [String: TOML.Value]?
    ) -> MCPDefinition? {
        if let object = claudeActive[name] ?? parked[name] { return Self.fromClaudeJSON(name: name, object: object) }
        if let codexTable { return Self.fromCodexTOML(name: name, table: codexTable) }
        return nil
    }

    // MARK: - Normalisation

    static func fromClaudeJSON(name: String, object: [String: Any]) -> MCPDefinition {
        let declared = (object["type"] as? String) ?? (object["transport"] as? String)
        let url = object["url"] as? String
        let transport = Transport(declared: declared, hasURL: url != nil)
        return MCPDefinition(
            name: name,
            transport: transport,
            command: object["command"] as? String,
            args: (object["args"] as? [Any])?.compactMap { $0 as? String } ?? [],
            environment: (object["env"] as? [String: Any])?.compactMapValues { $0 as? String } ?? [:],
            url: url
        )
    }

    static func fromCodexTOML(name: String, table: [String: TOML.Value]) -> MCPDefinition {
        let url = table["url"]?.stringValue
        let transport = Transport(declared: table["type"]?.stringValue, hasURL: url != nil)
        return MCPDefinition(
            name: name,
            transport: transport,
            command: table["command"]?.stringValue,
            args: table["args"]?.arrayValue?.compactMap { $0.stringValue } ?? [],
            environment: table["env"]?.tableValue?.compactMapValues { $0.stringValue } ?? [:],
            url: url
        )
    }

    private static func Transport(declared: String?, hasURL: Bool) -> MCPDefinition.Transport {
        if let declared, let t = MCPDefinition.Transport(rawValue: declared) { return t }
        return hasURL ? .http : .stdio
    }

    static func toClaudeJSON(_ definition: MCPDefinition) -> [String: Any] {
        var object: [String: Any] = ["type": definition.transport.rawValue]
        switch definition.transport {
        case .stdio:
            object["command"] = definition.command ?? ""
            object["args"] = definition.args
            if !definition.environment.isEmpty { object["env"] = definition.environment }
        case .http, .sse:
            object["url"] = definition.url ?? ""
        }
        return object
    }

    static func toCodexTOMLTable(_ definition: MCPDefinition) -> String {
        var lines = ["[\(codexTableRoot).\(definition.name)]"]
        lines.append("type = \(TOML.renderString(definition.transport.rawValue))")
        switch definition.transport {
        case .stdio:
            lines.append("command = \(TOML.renderString(definition.command ?? ""))")
            lines.append("args = [\(definition.args.map(TOML.renderString).joined(separator: ", "))]")
        case .http, .sse:
            lines.append("url = \(TOML.renderString(definition.url ?? ""))")
        }
        if !definition.environment.isEmpty {
            lines.append("")
            lines.append("[\(codexTableRoot).\(definition.name).env]")
            for key in definition.environment.keys.sorted() {
                lines.append("\(key) = \(TOML.renderString(definition.environment[key]!))")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Toggle

    public func setEnabled(_ enabled: Bool, name: String, agent: AgentKind) throws {
        switch agent {
        case .claude: try setClaudeEnabled(enabled, name: name)
        case .codex: try setCodexEnabled(enabled, name: name)
        }
    }

    private func setClaudeEnabled(_ enabled: Bool, name: String) throws {
        let root = (try? JSONConfig.read(env.claudeJSON)) ?? [:]
        var servers = (root["mcpServers"] as? [String: Any]) ?? [:]

        if enabled {
            guard servers[name] == nil else { return }
            let object: [String: Any]
            if let parkedObject = try? JSONConfig.read(parkedFile(name)), !parkedObject.isEmpty {
                object = parkedObject // Verbatim restore, including fields we never modelled.
            } else if let definition = codexDefinition(name: name) {
                object = Self.toClaudeJSON(definition)
            } else {
                throw SkillswitchError.refused("No parked or Codex definition for \"\(name)\" to enable.")
            }
            servers[name] = object
            try JSONConfig.setTopLevelValue(servers, forKey: "mcpServers", in: env.claudeJSON, env: env)
            if FileSafety.exists(parkedFile(name)) { try FileManager.default.removeItem(at: parkedFile(name)) }
        } else {
            guard let object = servers[name] as? [String: Any] else { return }
            // Park first: if this fails the server stays enabled rather than vanishing.
            try FileSafety.ensureDirectory(env.libraryParkedClaudeMCP)
            let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .withoutEscapingSlashes])
            try FileSafety.atomicWrite(data, to: parkedFile(name))
            guard let verified = try? JSONConfig.read(parkedFile(name)), JSONConfig.deepEqual(verified, object) else {
                try? FileManager.default.removeItem(at: parkedFile(name))
                throw SkillswitchError.io("Could not park \"\(name)\" safely; ~/.claude.json was left untouched.")
            }
            servers.removeValue(forKey: name)
            try JSONConfig.setTopLevelValue(servers, forKey: "mcpServers", in: env.claudeJSON, env: env)
        }
    }

    private func codexDefinition(name: String) -> MCPDefinition? {
        guard let text = try? String(contentsOf: env.codexConfigTOML, encoding: .utf8),
              let root = try? TOML.parse(text),
              let table = TOML.table(root, at: [Self.codexTableRoot, name]) else { return nil }
        return Self.fromCodexTOML(name: name, table: table)
    }

    private func setCodexEnabled(_ enabled: Bool, name: String) throws {
        let exists = FileSafety.exists(env.codexConfigTOML)
        let original = exists ? (try String(contentsOf: env.codexConfigTOML, encoding: .utf8)) : ""
        let root = try TOML.parse(original)
        let hasTable = TOML.table(root, at: [Self.codexTableRoot, name]) != nil

        let updated: String
        if hasTable {
            // `enabled` defaults to true, so enabling just removes the key rather than
            // leaving a redundant line behind.
            updated = try TOML.setKey(
                "enabled",
                to: enabled ? nil : "false",
                inTable: [Self.codexTableRoot, name],
                document: original
            )
        } else {
            guard enabled else { return }
            guard let definition = claudeDefinition(name: name) else {
                throw SkillswitchError.refused("No Claude definition for \"\(name)\" to convert into ~/.codex/config.toml.")
            }
            var text = original
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            if !text.isEmpty { text += "\n" }
            updated = text + Self.toCodexTOMLTable(definition) + "\n"
        }

        // Validate before writing: the document must still parse and must still contain every
        // server it had a moment ago.
        let reparsed = try TOML.parse(updated)
        let before = Set((TOML.table(root, at: [Self.codexTableRoot]) ?? [:]).keys)
        let after = Set((TOML.table(reparsed, at: [Self.codexTableRoot]) ?? [:]).keys)
        guard before.subtracting(after).isEmpty else {
            throw SkillswitchError.parse("The edit would have dropped MCP servers from config.toml; nothing was written.")
        }
        let expected = enabled ? nil : false
        guard TOML.table(reparsed, at: [Self.codexTableRoot, name])?["enabled"]?.boolValue == expected else {
            throw SkillswitchError.parse("The edit did not take effect as expected; nothing was written.")
        }

        if exists { try FileSafety.backup(env.codexConfigTOML, env: env) }
        try FileSafety.atomicWrite(Data(updated.utf8), to: env.codexConfigTOML)
    }

    private func claudeDefinition(name: String) -> MCPDefinition? {
        if let object = claudeServers()[name] { return Self.fromClaudeJSON(name: name, object: object) }
        if let object = try? JSONConfig.read(parkedFile(name)), !object.isEmpty {
            return Self.fromClaudeJSON(name: name, object: object)
        }
        return nil
    }
}
