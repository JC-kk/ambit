import Foundation

/// A Codex custom subagent ("agent role").
///
/// Verified against Codex 0.147 with `codex doctor`, which validates roles at startup:
///
/// * `~/.codex/config.toml` declares `[agents.<name>]` with `description`, `config_file` and an
///   optional `nickname_candidates`.
/// * `config_file` must point at an existing TOML file defining `name`, `description` and a
///   non-blank `developer_instructions`.
///
/// Getting either wrong produces `Ignoring malformed agent role definition: …` and a `⚠ config`
/// row in `codex doctor`, which is how the schema above was confirmed rather than guessed.
public struct CodexAgentRole: Sendable, Equatable {
    public var name: String
    public var description: String
    public var developerInstructions: String
    public var nicknameCandidates: [String]

    public init(name: String, description: String, developerInstructions: String, nicknameCandidates: [String] = []) {
        self.name = name
        self.description = description
        self.developerInstructions = developerInstructions
        self.nicknameCandidates = nicknameCandidates
    }

    /// Codex requires a non-blank `developer_instructions`, so an empty body is filled from the
    /// description rather than producing a file Codex will refuse.
    public init(fromClaudeMarkdown text: String, name: String) {
        let frontmatter = Frontmatter.parse(text)
        let body = Self.bodyAfterFrontmatter(text).trimmingCharacters(in: .whitespacesAndNewlines)
        let description = frontmatter["description"] ?? "Imported from the Claude subagent “\(name)”."
        self.init(
            name: name,
            description: description,
            developerInstructions: body.isEmpty ? description : body
        )
    }

    static func bodyAfterFrontmatter(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return text }
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return text
        }
        return lines[(close + 1)...].joined(separator: "\n")
    }

    /// The standalone role file `config_file` points at.
    public func renderRoleFile() -> String {
        var lines = [
            "# Codex agent role, managed by Agent Capability Manager.",
            "name = \(TOML.renderString(name))",
            "description = \(TOML.renderString(description))",
            "developer_instructions = \(TOML.renderPossiblyMultiline(developerInstructions))",
        ]
        if !nicknameCandidates.isEmpty {
            lines.append("nickname_candidates = [\(nicknameCandidates.map(TOML.renderString).joined(separator: ", "))]")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `[agents.<name>]` table that registers the role in `config.toml`.
    public func renderConfigTable(configFile: URL) -> String {
        var lines = [
            "[agents.\(TOML.renderKeyIfNeeded(name))]",
            "description = \(TOML.renderString(description))",
            "config_file = \(TOML.renderString(configFile.path))",
        ]
        if !nicknameCandidates.isEmpty {
            lines.append("nickname_candidates = [\(nicknameCandidates.map(TOML.renderString).joined(separator: ", "))]")
        }
        return lines.joined(separator: "\n")
    }

    public static func read(_ url: URL) -> CodexAgentRole? {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let table = try? TOML.parse(text) else { return nil }
        guard let name = table["name"]?.stringValue, !name.isEmpty else { return nil }
        return CodexAgentRole(
            name: name,
            description: table["description"]?.stringValue ?? "",
            developerInstructions: table["developer_instructions"]?.stringValue ?? "",
            nicknameCandidates: table["nickname_candidates"]?.arrayValue?.compactMap(\.stringValue) ?? []
        )
    }
}

extension TOML {
    /// Quotes a table-key segment only when TOML requires it.
    public static func renderKeyIfNeeded(_ key: String) -> String {
        key.allSatisfy(isBareKeyCharacter) && !key.isEmpty ? key : renderString(key)
    }
}
