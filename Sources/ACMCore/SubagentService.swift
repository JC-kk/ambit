import Foundation

/// Subagents, for both agents.
///
/// **Claude Code** reads `.md` files with YAML frontmatter from `~/.claude/agents/`. Exposure uses
/// **hard links**, not symlinks: Claude Code 2.1.234's agent directory walker does
/// `if (entry.isSymbolicLink()) continue`, so a symlinked agent is invisible. A hard link is a
/// regular file to every reader, shares its inode with the library copy, and unlinking it cannot
/// destroy that copy.
///
/// **Codex** reads agent roles declared as `[agents.<name>]` in `config.toml`, each pointing at a
/// role file via `config_file`. Exposure is therefore a config edit, not a link: enabling appends
/// the table, disabling lifts it out and parks the exact text for an identical restore.
///
/// The two formats are unrelated — Claude wants frontmatter plus a prompt body, Codex wants
/// `name`/`description`/`developer_instructions` — so a subagent enabled for both has one file per
/// agent, generated from whichever side already exists.
public struct SubagentService: Sendable {
    public let env: ACMEnvironment
    public init(env: ACMEnvironment) { self.env = env }

    static let agentsTableRoot = "agents"

    func claudeLibraryFile(_ name: String) -> URL { env.libraryClaudeAgents.appendingPathComponent("\(name).md") }
    func claudeExposedFile(_ name: String) -> URL { env.claudeAgentsDir.appendingPathComponent("\(name).md") }
    func codexLibraryFile(_ name: String) -> URL { env.libraryCodexAgents.appendingPathComponent("\(name).toml") }
    func codexParkedFile(_ name: String) -> URL {
        env.libraryCodexAgents.appendingPathComponent("parked").appendingPathComponent("\(name).toml")
    }

    // MARK: - Scan

    public func scan() -> (capabilities: [Capability], diagnostics: [Diagnostic]) {
        var diagnostics: [Diagnostic] = []

        let claudeLibrary = Set(markdownNames(in: env.libraryClaudeAgents))
        let claudeExposed = Set(markdownNames(in: env.claudeAgentsDir))
        let codexLibrary = Set(
            FileSafety.directoryEntries(env.libraryCodexAgents)
                .filter { $0.hasSuffix(".toml") }
                .map { ($0 as NSString).deletingPathExtension }
        )
        // A parked role has no file anywhere else, so without this it would drop out of the
        // inventory the moment it was disabled and could never be switched back on.
        let codexParked = Set(
            FileSafety.directoryEntries(env.libraryCodexAgents.appendingPathComponent("parked"))
                .filter { $0.hasSuffix(".toml") }
                .map { ($0 as NSString).deletingPathExtension }
        )

        var declaredRoles: [String: [String: TOML.Value]] = [:]
        if FileSafety.exists(env.codexConfigTOML) {
            do {
                let root = try TOML.parse(try String(contentsOf: env.codexConfigTOML, encoding: .utf8))
                for (name, value) in TOML.table(root, at: [Self.agentsTableRoot]) ?? [:] {
                    if let table = value.tableValue, table["config_file"] != nil || table["description"] != nil {
                        declaredRoles[name] = table
                    }
                }
            } catch {
                diagnostics.append(Diagnostic(
                    id: "subagents.codex-config-unparsed",
                    severity: .warning,
                    message: "Could not parse ~/.codex/config.toml (\(error.localizedDescription)). Codex subagent toggles are disabled until it parses cleanly."
                ))
            }
        }

        let names = claudeLibrary
            .union(claudeExposed)
            .union(codexLibrary)
            .union(codexParked)
            .union(declaredRoles.keys)
            .sorted()

        let capabilities = names.map { name -> Capability in
            let claudeLibrarySource = claudeLibrary.contains(name) ? claudeLibraryFile(name) : nil
            let claude = claudeExposure(name: name, librarySource: claudeLibrarySource)
            let codex = codexExposure(
                name: name,
                declared: declaredRoles[name],
                hasCodexLibrary: codexLibrary.contains(name),
                convertibleFrom: claudeLibrarySource ?? claude.exposurePath
            )

            let codexLibrarySource = codexLibrary.contains(name) ? codexLibraryFile(name) : nil
            let primary = claudeLibrarySource ?? codexLibrarySource ?? claude.exposurePath
            return Capability(
                kind: .subagent,
                name: name,
                summary: summary(name: name, claudeFile: primary, declared: declaredRoles[name]),
                librarySource: claudeLibrarySource ?? codexLibrarySource
                    ?? (codexParked.contains(name) ? codexParkedFile(name) : nil),
                primarySource: primary ?? env.codexConfigTOML,
                exposures: [.claude: claude, .codex: codex]
            )
        }
        return (capabilities, diagnostics)
    }

    private func summary(name: String, claudeFile: URL?, declared: [String: TOML.Value]?) -> String? {
        if let claudeFile, claudeFile.pathExtension == "md",
           let description = Frontmatter.read(claudeFile)["description"], !description.isEmpty {
            return description
        }
        if let role = CodexAgentRole.read(codexLibraryFile(name)), !role.description.isEmpty {
            return role.description
        }
        return declared?["description"]?.stringValue
    }

    // MARK: - Claude

    private func claudeExposure(name: String, librarySource: URL?) -> AgentExposure {
        let file = claudeExposedFile(name)
        guard FileSafety.exists(file) else {
            return AgentExposure(
                status: .off,
                detail: librarySource == nil ? "No Claude subagent in the library to expose." : nil,
                canToggle: librarySource != nil
            )
        }
        if FileSafety.isSymlink(file) {
            return AgentExposure(
                status: .broken, exposurePath: file,
                detail: "Symlink. Claude Code's agent scanner skips symlinks, so this never loads. Adopt it or replace it with a real file.",
                canToggle: false
            )
        }
        guard FileSafety.isRegularFile(file) else {
            return AgentExposure(status: .broken, exposurePath: file, detail: "Not a regular file.", canToggle: false)
        }
        if let librarySource, FileSafety.sameInode(file, librarySource) {
            return AgentExposure(status: .on, exposurePath: file, canToggle: true)
        }
        return AgentExposure(
            status: .external, exposurePath: file,
            detail: "A real file in ~/.claude/agents that this app did not create. Adopt links it into the library without moving or copying anything.",
            canToggle: false
        )
    }

    // MARK: - Codex

    private func codexExposure(
        name: String,
        declared: [String: TOML.Value]?,
        hasCodexLibrary: Bool,
        convertibleFrom claudeSource: URL?
    ) -> AgentExposure {
        guard let declared else {
            let canCreate = hasCodexLibrary || FileSafety.exists(codexParkedFile(name)) || claudeSource != nil
            return AgentExposure(
                status: .off,
                detail: canCreate
                    ? nil
                    : "No Codex agent role to expose. Codex roles need their own file — Claude's .md format is not compatible.",
                canToggle: canCreate
            )
        }

        guard let configFile = declared["config_file"]?.stringValue else {
            return AgentExposure(
                status: .broken, exposurePath: env.codexConfigTOML,
                detail: "[agents.\(name)] has no config_file, so Codex ignores it.", canToggle: false
            )
        }
        let url = URL(fileURLWithPath: configFile)
        guard FileSafety.exists(url) else {
            return AgentExposure(
                status: .broken, exposurePath: env.codexConfigTOML,
                detail: "config_file points at \(configFile), which does not exist. Codex logs “Ignoring malformed agent role definition”.",
                canToggle: true
            )
        }
        if FileSafety.isContained(url, in: env.libraryCodexAgents) {
            return AgentExposure(status: .on, exposurePath: env.codexConfigTOML, canToggle: true)
        }
        return AgentExposure(
            status: .external, exposurePath: url,
            detail: "Declared in ~/.codex/config.toml with a role file outside the library (\(configFile)). Turning it off parks the table so it can be restored exactly.",
            canToggle: true
        )
    }

    func markdownNames(in directory: URL) -> [String] {
        FileSafety.directoryEntries(directory)
            .filter { $0.hasSuffix(".md") }
            .map { ($0 as NSString).deletingPathExtension }
    }

    // MARK: - Toggle

    public func setEnabled(_ enabled: Bool, name: String, agent: AgentKind) throws {
        switch agent {
        case .claude: try setClaudeEnabled(enabled, name: name)
        case .codex: try setCodexEnabled(enabled, name: name)
        }
    }

    private func setClaudeEnabled(_ enabled: Bool, name: String) throws {
        let file = claudeExposedFile(name)
        let library = claudeLibraryFile(name)

        if enabled {
            guard FileSafety.isRegularFile(library) else {
                throw ACMError.refused("No Claude subagent named \"\(name)\" in the library. Use Adopt first.")
            }
            if FileSafety.exists(file) {
                guard FileSafety.sameInode(file, library) else {
                    throw ACMError.refused("\(file.path) already exists and is a different file. Resolve it by hand first.")
                }
                return
            }
            try FileSafety.createHardLink(at: file, target: library)
        } else {
            guard FileSafety.exists(file) else { return }
            try FileSafety.removeOwnedHardLink(file, librarySource: library)
        }
    }

    private func setCodexEnabled(_ enabled: Bool, name: String) throws {
        let original = FileSafety.exists(env.codexConfigTOML)
            ? (try String(contentsOf: env.codexConfigTOML, encoding: .utf8))
            : ""
        let root = try TOML.parse(original)
        let isDeclared = TOML.table(root, at: [Self.agentsTableRoot, name]) != nil

        let updated: String
        if enabled {
            if isDeclared, let existing = TOML.table(root, at: [Self.agentsTableRoot, name]),
               let path = existing["config_file"]?.stringValue, FileSafety.exists(URL(fileURLWithPath: path)) {
                return // Already live.
            }
            // Restore a parked declaration verbatim when we have one.
            if !isDeclared, let parked = try? String(contentsOf: codexParkedFile(name), encoding: .utf8), !parked.isEmpty {
                updated = TOML.appendTable(parked.trimmingCharacters(in: .newlines), to: original)
            } else {
                let role = try ensureCodexRoleFile(name: name)
                let table = role.renderConfigTable(configFile: codexLibraryFile(name))
                updated = isDeclared
                    ? TOML.appendTable(table, to: try TOML.removeTable([Self.agentsTableRoot, name], from: original).document)
                    : TOML.appendTable(table, to: original)
            }
        } else {
            guard isDeclared else { return }
            let (document, removed) = try TOML.removeTable([Self.agentsTableRoot, name], from: original)
            // Park before writing, so a failure here leaves the role enabled rather than lost.
            try FileSafety.ensureDirectory(codexParkedFile(name).deletingLastPathComponent())
            try FileSafety.atomicWrite(Data(removed.utf8), to: codexParkedFile(name))
            updated = document
        }

        try writeCodexConfig(updated, original: root, expectingDeclared: enabled, name: name)
        if enabled, FileSafety.exists(codexParkedFile(name)) {
            try? FileManager.default.removeItem(at: codexParkedFile(name))
        }
    }

    /// Makes sure a role file exists in the library, converting the Claude subagent if needed.
    private func ensureCodexRoleFile(name: String) throws -> CodexAgentRole {
        if let existing = CodexAgentRole.read(codexLibraryFile(name)) { return existing }

        let claudeSource = [claudeLibraryFile(name), claudeExposedFile(name)].first { FileSafety.isRegularFile($0) }
        guard let claudeSource, let text = try? String(contentsOf: claudeSource, encoding: .utf8) else {
            throw ACMError.refused("""
            No Codex role file for “\(name)” and no Claude subagent to convert from. \
            Codex roles need name, description and developer_instructions in their own TOML file.
            """)
        }
        let role = CodexAgentRole(fromClaudeMarkdown: text, name: name)
        try FileSafety.ensureDirectory(env.libraryCodexAgents)
        try FileSafety.atomicWrite(Data(role.renderRoleFile().utf8), to: codexLibraryFile(name))
        return role
    }

    /// Validates before writing: the document must still parse, every other declared role must
    /// survive, and this role must have ended up in the state we asked for.
    private func writeCodexConfig(_ updated: String, original: [String: TOML.Value], expectingDeclared: Bool, name: String) throws {
        let reparsed = try TOML.parse(updated)
        let before = Set((TOML.table(original, at: [Self.agentsTableRoot]) ?? [:]).keys).subtracting([name])
        let after = Set((TOML.table(reparsed, at: [Self.agentsTableRoot]) ?? [:]).keys)
        guard before.subtracting(after).isEmpty else {
            throw ACMError.parse("The edit would have dropped other agent roles from config.toml; nothing was written.")
        }
        let beforeServers = Set((TOML.table(original, at: ["mcp_servers"]) ?? [:]).keys)
        let afterServers = Set((TOML.table(reparsed, at: ["mcp_servers"]) ?? [:]).keys)
        guard beforeServers == afterServers else {
            throw ACMError.parse("The edit would have changed the MCP servers in config.toml; nothing was written.")
        }
        guard (TOML.table(reparsed, at: [Self.agentsTableRoot, name]) != nil) == expectingDeclared else {
            throw ACMError.parse("The edit did not take effect as expected; nothing was written.")
        }

        if FileSafety.exists(env.codexConfigTOML) { try FileSafety.backup(env.codexConfigTOML, env: env) }
        try FileSafety.atomicWrite(Data(updated.utf8), to: env.codexConfigTOML)
    }

    // MARK: - Adopt

    /// Links an existing `~/.claude/agents/<name>.md` into the library. Because a hard link shares
    /// the inode, nothing is copied, moved or deleted — the file simply becomes managed in place.
    public func adopt(name: String) throws {
        let file = claudeExposedFile(name)
        guard FileSafety.isRegularFile(file), !FileSafety.isSymlink(file) else {
            throw ACMError.refused("\(file.path) is not a regular file; there is nothing to adopt.")
        }
        let library = claudeLibraryFile(name)
        if FileSafety.exists(library) {
            guard FileSafety.sameInode(file, library) else {
                throw ACMError.refused("The library already has a different subagent named \"\(name)\".")
            }
            return
        }
        try FileSafety.ensureDirectory(env.libraryClaudeAgents)
        try FileSafety.createHardLink(at: library, target: file)
    }
}
