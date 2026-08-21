import Foundation

/// Every path the app is allowed to look at or touch.
///
/// Injectable so the whole of `SkillswitchCore` can be exercised against a throwaway fixture tree —
/// no test ever reads or writes the real `~/.claude`, `~/.codex` or `~/.agents`.
public struct SkillswitchEnvironment: Sendable {
    public var home: URL

    /// Central library. Deliberately outside every agent's discovery path.
    public var library: URL

    // Claude Code
    public var claudeHome: URL
    public var claudeSkillsDir: URL
    public var claudeAgentsDir: URL
    public var claudeSettings: URL
    public var claudeJSON: URL

    // Codex
    public var codexHome: URL
    public var codexSkillsDir: URL
    public var codexAgentsDir: URL
    public var codexConfigTOML: URL

    /// `~/.agents/skills` — a Codex discovery root that this app must never use as a store,
    /// but must know about in order to report forced-on skills honestly.
    public var sharedAgentsSkillsDir: URL

    public init(home: URL) {
        self.home = home
        library = home.appendingPathComponent(".skillswitch")

        claudeHome = home.appendingPathComponent(".claude")
        claudeSkillsDir = claudeHome.appendingPathComponent("skills")
        claudeAgentsDir = claudeHome.appendingPathComponent("agents")
        claudeSettings = claudeHome.appendingPathComponent("settings.json")
        claudeJSON = home.appendingPathComponent(".claude.json")

        codexHome = home.appendingPathComponent(".codex")
        codexSkillsDir = codexHome.appendingPathComponent("skills")
        codexAgentsDir = codexHome.appendingPathComponent("agents")
        codexConfigTOML = codexHome.appendingPathComponent("config.toml")

        sharedAgentsSkillsDir = home.appendingPathComponent(".agents").appendingPathComponent("skills")
    }

    public static var live: SkillswitchEnvironment {
        // SKILLSWITCH_HOME points the whole app at a throwaway tree, so the real config can be left alone
        // while trying things out.
        let processEnv = ProcessInfo.processInfo.environment
        let homePath = processEnv["SKILLSWITCH_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        var env = SkillswitchEnvironment(home: URL(fileURLWithPath: (homePath as NSString).expandingTildeInPath))
        // Honour CODEX_HOME the same way the Codex CLI does.
        if let codexHome = processEnv["CODEX_HOME"], !codexHome.isEmpty {
            let url = URL(fileURLWithPath: (codexHome as NSString).expandingTildeInPath)
            env.codexHome = url
            env.codexSkillsDir = url.appendingPathComponent("skills")
            env.codexAgentsDir = url.appendingPathComponent("agents")
            env.codexConfigTOML = url.appendingPathComponent("config.toml")
        }
        return env
    }

    // MARK: library sublocations

    public var librarySkills: URL { library.appendingPathComponent("skills") }
    public var libraryClaudeAgents: URL { library.appendingPathComponent("agents/claude") }
    public var libraryCodexAgents: URL { library.appendingPathComponent("agents/codex") }
    public var libraryParkedClaudeMCP: URL { library.appendingPathComponent("mcp/parked/claude") }
    public var libraryBackups: URL { library.appendingPathComponent("backups") }
}
