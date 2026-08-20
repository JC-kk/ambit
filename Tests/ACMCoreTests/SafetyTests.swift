import Testing
import Foundation
@testable import ACMCore

@Suite("Safety")
struct SafetyTests {

    @Test("A regular file or directory in a discovery path is never removed by the guards")
    func guardsRefuseRealEntries() throws {
        let f = try Fixture()
        let realDir = try f.makeSkill("real", in: f.env.claudeSkillsDir)
        #expect(throws: ACMError.self) {
            try FileSafety.removeOwnedSymlink(realDir, libraryRoot: f.env.librarySkills)
        }
        #expect(FileSafety.exists(realDir))

        let realFile = try f.makeAgentFile("real", in: f.env.claudeAgentsDir)
        let unrelated = try f.makeAgentFile("real", in: f.env.libraryClaudeAgents)
        #expect(throws: ACMError.self) {
            try FileSafety.removeOwnedHardLink(realFile, librarySource: unrelated)
        }
        #expect(FileSafety.exists(realFile))
    }

    @Test("The last remaining link to a file is never unlinked")
    func lastLinkIsProtected() throws {
        let f = try Fixture()
        let only = try f.makeAgentFile("solo", in: f.env.libraryClaudeAgents)
        #expect(throws: ACMError.self) {
            try FileSafety.removeOwnedHardLink(only, librarySource: only)
        }
        #expect(FileSafety.exists(only))
    }

    @Test("Editing one key leaves every other byte of the document identical")
    func jsonEditIsByteExact() throws {
        let f = try Fixture()
        // Doubles that Foundation's JSON writer does not round-trip exactly, plus key ordering and
        // indentation a whole-document rewrite would destroy.
        let original = """
        {
          "numStartups": 42,
          "lastSessionMetrics": {
            "frame_duration_ms_min": 0.06962500000008731,
            "frame_duration_ms_avg": 1.0463931895420722
          },
          "mcpServers": {
            "klaviyo": { "type": "http", "url": "https://mcp.klaviyo.com/mcp" },
            "shopify": { "type": "stdio", "command": "npx" }
          },
          "zzz_last": [1, 2, 3]
        }
        """
        try f.write(original, to: f.env.claudeJSON)

        var servers = try JSONConfig.read(f.env.claudeJSON)["mcpServers"] as? [String: Any] ?? [:]
        servers.removeValue(forKey: "klaviyo")
        try JSONConfig.setTopLevelValue(servers, forKey: "mcpServers", in: f.env.claudeJSON, env: f.env)

        let after = try f.read(f.env.claudeJSON)
        // The exact float text survives — a parse-and-reserialise would have written ...87311.
        #expect(after.contains("0.06962500000008731,"))
        #expect(after.contains("\"numStartups\": 42,"))
        #expect(after.contains("\"zzz_last\": [1, 2, 3]"))
        #expect(after.contains("klaviyo") == false)
        #expect(after.contains("shopify"))
        // Key order is untouched: numStartups still precedes lastSessionMetrics.
        #expect(after.range(of: "numStartups")!.lowerBound < after.range(of: "lastSessionMetrics")!.lowerBound)
    }

    @Test("A real ~/.claude.json-shaped document survives an MCP toggle round trip")
    func realShapedDocumentRoundTrips() throws {
        let f = try Fixture()
        try f.write("""
        {
          "numStartups": 7,
          "metrics": { "p50": 0.409458000001905, "p95": 4.054483199998504 },
          "mcpServers": { "klaviyo": { "type": "http", "url": "https://example.test/mcp" } },
          "oauthAccount": { "id": "keep-me" }
        }
        """, to: f.env.claudeJSON)
        let before = try f.read(f.env.claudeJSON)

        try f.store.mcp.setEnabled(false, name: "klaviyo", agent: .claude)
        #expect(try f.status(.mcp, "klaviyo", .claude) == .off)
        #expect(try f.read(f.env.claudeJSON).contains("0.409458000001905"))

        try f.store.mcp.setEnabled(true, name: "klaviyo", agent: .claude)
        #expect(try f.status(.mcp, "klaviyo", .claude) == .on)

        let after = try JSONConfig.read(f.env.claudeJSON)
        let original = try JSONSerialization.jsonObject(with: Data(before.utf8)) as? [String: Any] ?? [:]
        #expect(JSONConfig.deepEqual(after, original))
        #expect(try f.read(f.env.claudeJSON).contains("0.409458000001905"))
    }

    @Test("Every JSON config edit leaves a backup behind")
    func backupsAreWritten() throws {
        let f = try Fixture()
        try f.write(#"{"skillOverrides": {"a": "off"}}"#, to: f.env.claudeSettings)
        try ClaudeSettings.setSkillOverride("b", to: "off", env: f.env)

        let saved = FileSafety.directoryEntries(f.env.libraryBackups).flatMap {
            FileSafety.directoryEntries(f.env.libraryBackups.appendingPathComponent($0))
        }
        #expect(saved.contains { $0.contains("settings.json") })
    }

    @Test("Writing settings preserves every unrelated key")
    func settingsWritePreservesUnknownKeys() throws {
        let f = try Fixture()
        try f.write("""
        {
          "env": { "FOO": "bar" },
          "permissions": { "allow": ["Bash(git *)"] },
          "someFutureSetting": [1, 2, 3]
        }
        """, to: f.env.claudeSettings)

        try ClaudeSettings.setSkillOverride("seo", to: "off", env: f.env)

        let after = try JSONConfig.read(f.env.claudeSettings)
        #expect((after["env"] as? [String: Any])?["FOO"] as? String == "bar")
        #expect(((after["permissions"] as? [String: Any])?["allow"] as? [Any])?.count == 1)
        #expect((after["someFutureSetting"] as? [Any])?.count == 3)
        #expect((after["skillOverrides"] as? [String: Any])?["seo"] as? String == "off")

        // Clearing the last override removes the key rather than leaving an empty object.
        try ClaudeSettings.setSkillOverride("seo", to: nil, env: f.env)
        #expect(try JSONConfig.read(f.env.claudeSettings)["skillOverrides"] == nil)
    }

    @Test("An atomic write leaves no temp files and preserves file mode")
    func atomicWriteIsClean() throws {
        let f = try Fixture()
        let target = f.home.appendingPathComponent("config/thing.json")
        try f.write("{}", to: target)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o600)], ofItemAtPath: target.path)

        try FileSafety.atomicWrite(Data(#"{"a":1}"#.utf8), to: target)

        #expect(try f.read(target) == #"{"a":1}"#)
        let mode = FileSafety.lstat(target).map { $0.st_mode & 0o777 }
        #expect(mode == 0o600)
        let leftovers = (try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path))
            .filter { $0.hasPrefix(".acm-") }
        #expect(leftovers.isEmpty)
    }

    @Test("The store refuses toggles the scan marked as untoggleable")
    func storeRespectsCanToggle() throws {
        let f = try Fixture()
        try f.makeSkill("vendor", in: f.env.codexSkillsDir)
        let capability = try f.capability(.skill, "vendor")
        #expect(capability.exposure(.codex).canToggle == false)
        #expect(throws: ACMError.self) {
            try f.store.setEnabled(false, capability: capability, agent: .codex)
        }
        #expect(FileSafety.exists(f.env.codexSkillsDir.appendingPathComponent("vendor/SKILL.md")))
    }

    @Test("Preparing the library creates only library directories")
    func prepareLibraryIsSelfContained() throws {
        let home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acm-prepare-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let env = ACMEnvironment(home: home)
        try CapabilityStore(env: env).prepareLibrary()

        #expect(FileSafety.isDirectory(env.librarySkills))
        #expect(!FileSafety.exists(env.claudeHome))
        #expect(!FileSafety.exists(env.codexHome))
        #expect(!FileSafety.exists(home.appendingPathComponent(".agents")))
    }
}
