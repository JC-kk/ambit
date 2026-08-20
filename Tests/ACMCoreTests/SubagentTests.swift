import Testing
import Foundation
@testable import ACMCore

@Suite("Subagents")
struct SubagentTests {

    @Test("A library subagent toggles into ~/.claude/agents as a hard link, not a symlink")
    func exposureIsAHardLink() throws {
        let f = try Fixture()
        try f.makeAgentFile("seo-technical", in: f.env.libraryClaudeAgents)

        #expect(try f.status(.subagent, "seo-technical", .claude) == .off)
        try f.store.subagents.setEnabled(true, name: "seo-technical", agent: .claude)

        let exposed = f.env.claudeAgentsDir.appendingPathComponent("seo-technical.md")
        let library = f.env.libraryClaudeAgents.appendingPathComponent("seo-technical.md")
        #expect(try f.status(.subagent, "seo-technical", .claude) == .on)
        // Claude Code's agent walker skips symlinks, so this must be a real file.
        #expect(!FileSafety.isSymlink(exposed))
        #expect(FileSafety.isRegularFile(exposed))
        #expect(FileSafety.sameInode(exposed, library))
    }

    @Test("Disabling unlinks the exposure and never touches the library copy")
    func disableKeepsLibraryCopy() throws {
        let f = try Fixture()
        let library = try f.makeAgentFile("seo-schema", in: f.env.libraryClaudeAgents)
        try f.store.subagents.setEnabled(true, name: "seo-schema", agent: .claude)
        try f.store.subagents.setEnabled(false, name: "seo-schema", agent: .claude)

        #expect(!FileSafety.exists(f.env.claudeAgentsDir.appendingPathComponent("seo-schema.md")))
        #expect(FileSafety.isRegularFile(library))
        #expect(try f.read(library).contains("You are a test agent."))
    }

    @Test("An unmanaged .md in ~/.claude/agents is EXTERNAL and cannot be deleted")
    func externalAgentIsNeverDeleted() throws {
        let f = try Fixture()
        let existing = try f.makeAgentFile("seo-backlinks", in: f.env.claudeAgentsDir)

        let capability = try f.capability(.subagent, "seo-backlinks")
        #expect(capability.exposure(.claude).status == .external)
        #expect(capability.exposure(.claude).canToggle == false)

        #expect(throws: ACMError.self) {
            try f.store.subagents.setEnabled(false, name: "seo-backlinks", agent: .claude)
        }
        #expect(FileSafety.exists(existing))
    }

    @Test("A file that merely shares a name is refused, not overwritten or unlinked")
    func nameCollisionIsRefused() throws {
        let f = try Fixture()
        try f.makeAgentFile("clash", in: f.env.libraryClaudeAgents, description: "Library version.")
        try f.makeAgentFile("clash", in: f.env.claudeAgentsDir, description: "Someone else's version.")

        #expect(throws: ACMError.self) {
            try f.store.subagents.setEnabled(true, name: "clash", agent: .claude)
        }
        #expect(throws: ACMError.self) {
            try f.store.subagents.setEnabled(false, name: "clash", agent: .claude)
        }
        let exposed = try f.read(f.env.claudeAgentsDir.appendingPathComponent("clash.md"))
        #expect(exposed.contains("Someone else's version."))
    }

    @Test("Adopt links an existing agent into the library without copying or moving it")
    func adoptIsInPlace() throws {
        let f = try Fixture()
        let existing = try f.makeAgentFile("seo-local", in: f.env.claudeAgentsDir, description: "Adopt me.")
        let before = try f.read(existing)

        try f.store.subagents.adopt(name: "seo-local")

        let library = f.env.libraryClaudeAgents.appendingPathComponent("seo-local.md")
        #expect(FileSafety.sameInode(existing, library))
        #expect(try f.read(existing) == before)
        #expect(try f.status(.subagent, "seo-local", .claude) == .on)

        // Now it behaves like any other managed subagent.
        try f.store.subagents.setEnabled(false, name: "seo-local", agent: .claude)
        #expect(!FileSafety.exists(existing))
        #expect(try f.read(library) == before)

        try f.store.subagents.setEnabled(true, name: "seo-local", agent: .claude)
        #expect(try f.read(existing) == before)
    }

    @Test("A symlinked agent reads BROKEN because Claude's scanner skips symlinks")
    func symlinkedAgentIsBroken() throws {
        let f = try Fixture()
        let library = try f.makeAgentFile("linked", in: f.env.libraryClaudeAgents)
        try FileSafety.createSymlink(
            at: f.env.claudeAgentsDir.appendingPathComponent("linked.md"),
            target: library
        )
        let exposure = try f.capability(.subagent, "linked").exposure(.claude)
        #expect(exposure.status == .broken)
        #expect(exposure.canToggle == false)
    }

    @Test("Enabling Codex converts the Claude subagent into a role Codex actually accepts")
    func codexRoleIsGeneratedFromClaude() throws {
        let f = try Fixture()
        try f.write("model = \"gpt-5.6-sol\"\n", to: f.env.codexConfigTOML)
        try f.write("""
        ---
        name: seo-technical
        description: Technical SEO specialist.
        ---

        You are a technical SEO specialist. Analyse crawlability and indexability.
        """, to: f.env.libraryClaudeAgents.appendingPathComponent("seo-technical.md"))

        #expect(try f.status(.subagent, "seo-technical", .codex) == .off)
        try f.store.subagents.setEnabled(true, name: "seo-technical", agent: .codex)
        #expect(try f.status(.subagent, "seo-technical", .codex) == .on)

        // The role file carries exactly the three fields Codex validates.
        let roleFile = f.env.libraryCodexAgents.appendingPathComponent("seo-technical.toml")
        let role = try #require(CodexAgentRole.read(roleFile))
        #expect(role.name == "seo-technical")
        #expect(role.description == "Technical SEO specialist.")
        #expect(role.developerInstructions.contains("crawlability"))
        #expect(!role.developerInstructions.isEmpty)

        // And config.toml declares it pointing at that file.
        let config = try f.read(f.env.codexConfigTOML)
        #expect(config.contains("[agents.seo-technical]"))
        #expect(config.contains("config_file = \"\(roleFile.path)\""))
        #expect(config.contains("model = \"gpt-5.6-sol\""))
    }

    @Test("Claude and Codex subagents toggle independently")
    func independentToggles() throws {
        let f = try Fixture()
        try f.write("model = \"x\"\n", to: f.env.codexConfigTOML)
        try f.makeAgentFile("seo-geo", in: f.env.libraryClaudeAgents, description: "GEO specialist.")

        try f.store.subagents.setEnabled(true, name: "seo-geo", agent: .claude)
        try f.store.subagents.setEnabled(true, name: "seo-geo", agent: .codex)
        #expect(try f.status(.subagent, "seo-geo", .claude) == .on)
        #expect(try f.status(.subagent, "seo-geo", .codex) == .on)

        try f.store.subagents.setEnabled(false, name: "seo-geo", agent: .claude)
        #expect(try f.status(.subagent, "seo-geo", .claude) == .off)
        #expect(try f.status(.subagent, "seo-geo", .codex) == .on)
        #expect(FileSafety.exists(f.env.libraryClaudeAgents.appendingPathComponent("seo-geo.md")))
        #expect(FileSafety.exists(f.env.libraryCodexAgents.appendingPathComponent("seo-geo.toml")))
    }

    @Test("Disabling a Codex role parks the table and restores it verbatim")
    func codexParkAndRestore() throws {
        let f = try Fixture()
        let roleFile = f.home.appendingPathComponent("custom/reviewer.toml")
        try f.write("name = \"reviewer\"\ndescription = \"d\"\ndeveloper_instructions = \"i\"\n", to: roleFile)
        try f.write("""
        # keep this comment
        model = "gpt-5.6-sol"

        [mcp_servers.shopify]
        command = "npx"

        [agents.reviewer]
        description = "Reviews code carefully."
        config_file = "\(roleFile.path)"
        nickname_candidates = ["Rex", "Robin"]

        [projects."/Users/test"]
        trust_level = "trusted"
        """, to: f.env.codexConfigTOML)

        #expect(try f.status(.subagent, "reviewer", .codex) == .external)

        try f.store.subagents.setEnabled(false, name: "reviewer", agent: .codex)
        #expect(try f.status(.subagent, "reviewer", .codex) == .off)
        var config = try f.read(f.env.codexConfigTOML)
        #expect(!config.contains("[agents.reviewer]"))
        #expect(config.contains("# keep this comment"))
        #expect(config.contains("[mcp_servers.shopify]"))
        #expect(config.contains("[projects.\"/Users/test\"]"))

        try f.store.subagents.setEnabled(true, name: "reviewer", agent: .codex)
        config = try f.read(f.env.codexConfigTOML)
        #expect(config.contains("[agents.reviewer]"))
        #expect(config.contains("description = \"Reviews code carefully.\""))
        #expect(config.contains("nickname_candidates = [\"Rex\", \"Robin\"]"))
        #expect(config.contains("config_file = \"\(roleFile.path)\""))
        #expect(try f.status(.subagent, "reviewer", .codex) == .external)
    }

    @Test("A role whose config_file is missing reads BROKEN")
    func brokenRole() throws {
        let f = try Fixture()
        try f.write("""
        [agents.ghost]
        description = "Gone."
        config_file = "/definitely/not/here.toml"
        """, to: f.env.codexConfigTOML)

        let exposure = try f.capability(.subagent, "ghost").exposure(.codex)
        #expect(exposure.status == .broken)
        #expect(exposure.detail?.contains("does not exist") == true)
    }

    @Test("Codex cannot be enabled with nothing to build a role from")
    func codexNeedsASource() throws {
        let f = try Fixture()
        try f.write("model = \"x\"\n", to: f.env.codexConfigTOML)
        try f.makeAgentFile("orphan", in: f.env.libraryClaudeAgents)
        try FileManager.default.removeItem(at: f.env.libraryClaudeAgents.appendingPathComponent("orphan.md"))

        #expect(throws: ACMError.self) {
            try f.store.subagents.setEnabled(true, name: "orphan", agent: .codex)
        }
    }

    @Test("Frontmatter descriptions reach the inventory")
    func summariesAreRead() throws {
        let f = try Fixture()
        try f.makeAgentFile("seo-geo", in: f.env.libraryClaudeAgents, description: "GEO and AI search specialist.")
        #expect(try f.capability(.subagent, "seo-geo").summary == "GEO and AI search specialist.")
    }
}
