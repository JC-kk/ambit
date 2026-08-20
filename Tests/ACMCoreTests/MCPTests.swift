import Testing
import Foundation
@testable import ACMCore

@Suite("MCP")
struct MCPTests {

    /// A config.toml shaped like the real one: comments, unrelated tables, an already-disabled
    /// server, nested env tables, multi-line arrays.
    static let codexConfig = """
    # Personal Codex settings — do not lose this comment.
    notify = ["client", "turn-ended"]
    model = "gpt-5.6-sol"

    [mcp_servers]

    [mcp_servers.computer-use]
    command = "./Computer Use.app/Contents/MacOS/Client"
    args = ["mcp"]
    cwd = "."
    enabled = false

    [mcp_servers.shopify]
    type = "stdio"
    command = "npx"
    args = [
      "-y",
      "@shopify/dev-mcp@latest",
    ]

    [mcp_servers.node_repl]
    command = "/usr/local/bin/node_repl"
    startup_timeout_sec = 120

    [mcp_servers.node_repl.env]
    NODE_REPL_NODE_PATH = "/usr/local/bin/node"
    CODEX_HOME = "/Users/test/.codex"

    [projects."/Users/test/work"]
    trust_level = "trusted"
    """

    @Test("Codex servers read their native enabled flag")
    func codexStatuses() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)

        #expect(try f.status(.mcp, "shopify", .codex) == .on)
        #expect(try f.status(.mcp, "node_repl", .codex) == .on)
        #expect(try f.status(.mcp, "computer-use", .codex) == .off)
    }

    @Test("Disabling a Codex server flips one key and leaves every other byte alone")
    func codexDisableIsSurgical() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)

        try f.store.mcp.setEnabled(false, name: "shopify", agent: .codex)
        let after = try f.read(f.env.codexConfigTOML)

        #expect(try f.status(.mcp, "shopify", .codex) == .off)
        #expect(after.contains("# Personal Codex settings — do not lose this comment."))
        #expect(after.contains("startup_timeout_sec = 120"))
        #expect(after.contains("NODE_REPL_NODE_PATH = \"/usr/local/bin/node\""))
        #expect(after.contains("[projects.\"/Users/test/work\"]"))
        #expect(after.contains("\"@shopify/dev-mcp@latest\","))

        // Nothing else moved: the only difference is the added line.
        let removed = Self.codexConfig.components(separatedBy: "\n")
            .filter { line in !after.components(separatedBy: "\n").contains(line) }
        #expect(removed.isEmpty)
    }

    @Test("Enabling a Codex server removes the flag rather than writing enabled = true")
    func codexEnableRemovesFlag() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)

        try f.store.mcp.setEnabled(true, name: "computer-use", agent: .codex)
        let after = try f.read(f.env.codexConfigTOML)

        #expect(try f.status(.mcp, "computer-use", .codex) == .on)
        #expect(!after.contains("enabled = false"))
        #expect(after.contains("command = \"./Computer Use.app/Contents/MacOS/Client\""))
    }

    @Test("A Codex config edit is backed up first")
    func codexEditIsBackedUp() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)
        try f.store.mcp.setEnabled(false, name: "shopify", agent: .codex)

        let stamps = FileSafety.directoryEntries(f.env.libraryBackups)
        #expect(!stamps.isEmpty)
        let saved = stamps.flatMap { stamp in
            FileSafety.directoryEntries(f.env.libraryBackups.appendingPathComponent(stamp))
        }
        #expect(saved.contains { $0.contains("config.toml") })
    }

    @Test("Disabling a Claude server parks it verbatim, including fields we never modelled")
    func claudeParkIsVerbatim() throws {
        let f = try Fixture()
        try f.write("""
        {
          "numStartups": 42,
          "mcpServers": {
            "klaviyo": {
              "type": "http",
              "url": "https://mcp.klaviyo.com/mcp?core-tools-only=true",
              "someFutureField": { "nested": [1, 2, 3] }
            },
            "shopify": { "type": "stdio", "command": "npx", "args": ["-y", "x"] }
          },
          "oauthAccount": { "id": "keep-me" }
        }
        """, to: f.env.claudeJSON)

        #expect(try f.status(.mcp, "klaviyo", .claude) == .on)
        try f.store.mcp.setEnabled(false, name: "klaviyo", agent: .claude)
        #expect(try f.status(.mcp, "klaviyo", .claude) == .off)

        // Gone from the live config, intact in the parking lot.
        let root = try JSONConfig.read(f.env.claudeJSON)
        let servers = root["mcpServers"] as? [String: Any] ?? [:]
        #expect(servers["klaviyo"] == nil)
        #expect(servers["shopify"] != nil)
        #expect((root["oauthAccount"] as? [String: Any])?["id"] as? String == "keep-me")
        #expect(root["numStartups"] as? Int == 42)

        let parked = try JSONConfig.read(f.env.libraryParkedClaudeMCP.appendingPathComponent("klaviyo.json"))
        #expect(parked["url"] as? String == "https://mcp.klaviyo.com/mcp?core-tools-only=true")
        #expect(((parked["someFutureField"] as? [String: Any])?["nested"] as? [Any])?.count == 3)

        // Re-enabling restores the object byte-for-byte in content.
        try f.store.mcp.setEnabled(true, name: "klaviyo", agent: .claude)
        let restored = (try JSONConfig.read(f.env.claudeJSON)["mcpServers"] as? [String: Any])?["klaviyo"]
        #expect(JSONConfig.deepEqual(restored, parked))
        #expect(!FileSafety.exists(f.env.libraryParkedClaudeMCP.appendingPathComponent("klaviyo.json")))
    }

    @Test("A server defined only for Codex can be converted into Claude's config")
    func crossAgentConversionToClaude() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)
        try f.write("{}", to: f.env.claudeJSON)

        #expect(try f.status(.mcp, "shopify", .claude) == .off)
        try f.store.mcp.setEnabled(true, name: "shopify", agent: .claude)

        let servers = try JSONConfig.read(f.env.claudeJSON)["mcpServers"] as? [String: Any] ?? [:]
        let shopify = servers["shopify"] as? [String: Any]
        #expect(shopify?["type"] as? String == "stdio")
        #expect(shopify?["command"] as? String == "npx")
        #expect((shopify?["args"] as? [Any])?.count == 2)
    }

    @Test("A server defined only for Claude can be appended to config.toml")
    func crossAgentConversionToCodex() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)
        try f.write("""
        { "mcpServers": { "robinhood": { "type": "http", "url": "https://agent.robinhood.com/mcp/trading" } } }
        """, to: f.env.claudeJSON)

        #expect(try f.status(.mcp, "robinhood", .codex) == .off)
        try f.store.mcp.setEnabled(true, name: "robinhood", agent: .codex)

        #expect(try f.status(.mcp, "robinhood", .codex) == .on)
        let after = try f.read(f.env.codexConfigTOML)
        #expect(after.contains("[mcp_servers.robinhood]"))
        #expect(after.contains("url = \"https://agent.robinhood.com/mcp/trading\""))
        // Pre-existing servers all survived.
        #expect(try f.status(.mcp, "shopify", .codex) == .on)
        #expect(try f.status(.mcp, "computer-use", .codex) == .off)
    }

    @Test("An unparseable config.toml disables Codex toggles instead of guessing")
    func unparseableConfigIsReported() throws {
        let f = try Fixture()
        try f.write("this is not = = valid toml [[[\n", to: f.env.codexConfigTOML)
        let inventory = f.store.scan()
        #expect(inventory.diagnostics.contains { $0.id == "mcp.codex-config-unparsed" })
    }

    @Test("Toggling a Codex server that does not exist anywhere is refused")
    func unknownServerRefused() throws {
        let f = try Fixture()
        try f.write(Self.codexConfig, to: f.env.codexConfigTOML)
        #expect(throws: ACMError.self) {
            try f.store.mcp.setEnabled(true, name: "does-not-exist", agent: .codex)
        }
    }
}
