import Testing
import Foundation
@testable import AmbitCore

@Suite("Bulk toggle")
struct BulkToggleTests {

    @Test("A column reads allOff, mixed then allOn as it fills up")
    func stateTracksTheColumn() throws {
        let f = try Fixture()
        for name in ["alpha", "beta", "gamma"] { try f.makeLibrarySkill(name) }

        #expect(f.store.scan().of(.skill).bulkState(for: .claude) == .allOff)

        try f.store.skills.setEnabled(true, name: "beta", agent: .claude)
        #expect(f.store.scan().of(.skill).bulkState(for: .claude) == .mixed)
        // The other agent is untouched by the first one filling up.
        #expect(f.store.scan().of(.skill).bulkState(for: .codex) == .allOff)

        for name in ["alpha", "gamma"] { try f.store.skills.setEnabled(true, name: name, agent: .claude) }
        #expect(f.store.scan().of(.skill).bulkState(for: .claude) == .allOn)
    }

    @Test("Rows this app cannot move are left out of the total, not counted as off")
    func ungovernedRowsDoNotBlockAllOn() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("mine")
        // Discoverable by Codex through the shared root, and not ours to switch off.
        try f.makeSkill("forced", in: f.env.sharedAgentsSkillsDir)

        let skills = f.store.scan().of(.skill)
        #expect(skills.count == 2)
        #expect(try f.status(.skill, "forced", .codex) == .external)
        #expect(skills.first { $0.name == "forced" }?.exposure(.codex).canToggle == false)

        // One governed row, still off.
        #expect(skills.bulkState(for: .codex) == .allOff)
        try f.store.skills.setEnabled(true, name: "mine", agent: .codex)
        #expect(f.store.scan().of(.skill).bulkState(for: .codex) == .allOn)
    }

    @Test("A column with nothing togglable reads unavailable")
    func nothingToDoReadsUnavailable() throws {
        let f = try Fixture()
        try f.makeSkill("vendor", in: f.env.sharedAgentsSkillsDir)
        #expect(f.store.scan().of(.skill).bulkState(for: .codex) == .unavailable)
    }

    @Test("Setting a whole column on skips what it cannot move and reports nothing")
    func setAllSkipsQuietly() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("one")
        try f.makeLibrarySkill("two")
        try f.makeSkill("forced", in: f.env.sharedAgentsSkillsDir)

        let skills = f.store.scan().of(.skill)
        let failures = f.store.setAll(true, capabilities: skills, agent: .codex)
        #expect(failures.isEmpty)
        #expect(f.store.scan().of(.skill).bulkState(for: .codex) == .allOn)
        #expect(try f.status(.skill, "one", .codex) == .on)
        #expect(try f.status(.skill, "two", .codex) == .on)
        // Untouched: the other agent was never asked.
        #expect(try f.status(.skill, "one", .claude) == .off)
    }

    @Test("An explicit selection does report what it left alone")
    func setAllReportsSkipsWhenAsked() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("one")
        try f.makeSkill("forced", in: f.env.sharedAgentsSkillsDir)

        let skills = f.store.scan().of(.skill)
        let failures = f.store.setAll(false, capabilities: skills, agent: .codex, reportingSkips: true)
        #expect(failures.count == 1)
        #expect(failures[0].contains("forced"))
    }

    @Test("Turning a whole column off leaves every library source in place")
    func setAllOffKeepsSources() throws {
        let f = try Fixture()
        for name in ["one", "two"] { try f.makeLibrarySkill(name) }
        _ = f.store.setAll(true, capabilities: f.store.scan().of(.skill), agent: .claude)
        _ = f.store.setAll(false, capabilities: f.store.scan().of(.skill), agent: .claude)

        #expect(f.store.scan().of(.skill).bulkState(for: .claude) == .allOff)
        for name in ["one", "two"] {
            #expect(FileSafety.exists(f.env.librarySkills.appendingPathComponent(name)))
        }
        #expect(f.store.scan().diagnostics.isEmpty)
    }

    @Test("MCP and subagents get the same column treatment as skills")
    func everyKindHasAColumn() throws {
        let f = try Fixture()
        try f.write("""
        { "mcpServers": { "shopify": { "type": "stdio", "command": "npx", "args": ["-y", "x"] } } }
        """, to: f.env.claudeJSON)
        try f.makeAgentFile("reviewer", in: f.env.libraryClaudeAgents)
        try f.makeLibrarySkill("notes")

        let inventory = f.store.scan()
        #expect(inventory.of(.mcp).bulkState(for: .claude) == .allOn)
        #expect(inventory.of(.mcp).bulkState(for: .codex) == .allOff)
        #expect(inventory.of(.subagent).bulkState(for: .claude) == .allOff)
        #expect(inventory.of(.skill).bulkState(for: .claude) == .allOff)

        for kind in CapabilityKind.allCases {
            _ = f.store.setAll(true, capabilities: inventory.of(kind), agent: .claude)
        }
        let after = f.store.scan()
        for kind in CapabilityKind.allCases {
            #expect(after.of(kind).bulkState(for: .claude) == .allOn, "\(kind.rawValue) should be all on")
        }
    }
}
