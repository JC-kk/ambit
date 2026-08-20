import Testing
import Foundation
@testable import AmbitCore

@Suite("Consolidation")
struct ConsolidationTests {

    /// Reproduces the real machine: ~/.claude/skills is a symlink to ~/.agents/skills, which Codex
    /// also scans, so every skill is forced on for both agents.
    private func aliasedFixture() throws -> Fixture {
        let f = try Fixture()
        try FileManager.default.removeItem(at: f.env.claudeSkillsDir)
        try FileSafety.ensureDirectory(f.env.sharedAgentsSkillsDir)
        try FileSafety.createSymlink(at: f.env.claudeSkillsDir, target: f.env.sharedAgentsSkillsDir)
        return f
    }

    @Test("Consolidating the aliased layout gives genuinely independent switches")
    func aliasedLayoutBecomesIndependent() throws {
        let f = try aliasedFixture()
        try f.makeSkill("seo", in: f.env.sharedAgentsSkillsDir, description: "SEO analysis.")
        try f.makeSkill("schema", in: f.env.sharedAgentsSkillsDir)

        // Before: both agents forced on, no toggle possible.
        #expect(try f.status(.skill, "seo", .claude) == .external)
        #expect(try f.capability(.skill, "seo").exposure(.codex).canToggle == false)

        let plan = f.store.consolidation.plan()
        #expect(plan.replacesClaudeSkillsSymlink)
        #expect(plan.moves(.skill).count == 2)
        #expect(plan.moves(.skill).allSatisfy { $0.relinkTo == [.claude, .codex] })
        try f.store.consolidation.apply(plan)

        // After: one source in the library, a link in each agent, and both toggles live.
        #expect(FileSafety.exists(f.env.librarySkills.appendingPathComponent("seo/SKILL.md")))
        #expect(!FileSafety.isSymlink(f.env.claudeSkillsDir))
        #expect(FileSafety.directoryEntries(f.env.sharedAgentsSkillsDir).isEmpty)

        #expect(try f.status(.skill, "seo", .claude) == .on)
        #expect(try f.status(.skill, "seo", .codex) == .on)
        #expect(f.store.scan().diagnostics.isEmpty)

        try f.store.skills.setEnabled(false, name: "seo", agent: .codex)
        #expect(try f.status(.skill, "seo", .claude) == .on)
        #expect(try f.status(.skill, "seo", .codex) == .off)
        #expect(FileSafety.exists(f.env.librarySkills.appendingPathComponent("seo/SKILL.md")))
    }

    @Test("Consolidation preserves exactly what each agent could see")
    func exposureIsPreserved() throws {
        let f = try Fixture()
        try f.makeSkill("claude-only", in: f.env.claudeSkillsDir)
        try f.makeSkill("codex-only", in: f.env.codexSkillsDir)

        try f.store.consolidation.apply(f.store.consolidation.plan())

        #expect(try f.status(.skill, "claude-only", .claude) == .on)
        #expect(try f.status(.skill, "claude-only", .codex) == .off)
        #expect(try f.status(.skill, "codex-only", .claude) == .off)
        #expect(try f.status(.skill, "codex-only", .codex) == .on)
    }

    @Test("Two separate copies of one name: one becomes canonical, the other is parked not deleted")
    func duplicatesAreParked() throws {
        let f = try Fixture()
        try f.makeSkill("dup", in: f.env.claudeSkillsDir, description: "Claude copy.")
        try f.makeSkill("dup", in: f.env.codexSkillsDir, description: "Codex copy.")

        let plan = f.store.consolidation.plan()
        #expect(plan.moves(.skill).first?.parked.count == 1)
        try f.store.consolidation.apply(plan)

        #expect(try f.read(f.env.librarySkills.appendingPathComponent("dup/SKILL.md")).contains("Claude copy."))
        #expect(try f.status(.skill, "dup", .claude) == .on)
        #expect(try f.status(.skill, "dup", .codex) == .on)

        // The Codex copy still exists, parked under backups.
        let parked = FileSafety.directoryEntries(f.env.libraryBackups).flatMap { stamp in
            FileSafety.directoryEntries(f.env.libraryBackups.appendingPathComponent(stamp))
        }
        #expect(parked.contains { $0.hasPrefix("duplicate-dup") })
    }

    @Test("Subagents move into the library and keep working through a hard link")
    func subagentsAreConsolidated() throws {
        let f = try Fixture()
        let original = try f.makeAgentFile("seo-technical", in: f.env.claudeAgentsDir, description: "Technical SEO.")
        let before = try f.read(original)

        try f.store.consolidation.apply(f.store.consolidation.plan())

        let library = f.env.libraryClaudeAgents.appendingPathComponent("seo-technical.md")
        let exposed = f.env.claudeAgentsDir.appendingPathComponent("seo-technical.md")
        #expect(try f.read(library) == before)
        #expect(FileSafety.sameInode(library, exposed))
        #expect(!FileSafety.isSymlink(exposed))
        #expect(try f.status(.subagent, "seo-technical", .claude) == .on)

        try f.store.subagents.setEnabled(false, name: "seo-technical", agent: .claude)
        #expect(!FileSafety.exists(exposed))
        #expect(try f.read(library) == before)
    }

    @Test("Symlinks, library copies and Codex's bundled skills are left alone")
    func alreadyManagedAndBundledAreSkipped() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("managed")
        try f.store.skills.setEnabled(true, name: "managed", agent: .claude)
        try f.makeSkill("bundled", in: f.env.codexSkillsDir.appendingPathComponent(".system"))

        let plan = f.store.consolidation.plan()
        #expect(plan.moves.isEmpty)
        #expect(plan.isEmpty)
    }

    @Test("A name already in the library is reported as blocked and nothing is moved")
    func libraryCollisionIsBlocked() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("clash", description: "Library copy.")
        try f.makeSkill("clash", in: f.env.codexSkillsDir, description: "Codex copy.")

        let plan = f.store.consolidation.plan()
        #expect(plan.moves.isEmpty)
        #expect(plan.blocked.count == 1)
        try f.store.consolidation.apply(plan)

        #expect(try f.read(f.env.librarySkills.appendingPathComponent("clash/SKILL.md")).contains("Library copy."))
        #expect(try f.read(f.env.codexSkillsDir.appendingPathComponent("clash/SKILL.md")).contains("Codex copy."))
    }

    @Test("Every move is recorded in a manifest")
    func manifestIsWritten() throws {
        let f = try aliasedFixture()
        try f.makeSkill("seo", in: f.env.sharedAgentsSkillsDir)
        try f.makeAgentFile("seo-geo", in: f.env.claudeAgentsDir)

        let manifest = try f.store.consolidation.apply(f.store.consolidation.plan())
        let object = try JSONConfig.read(manifest)
        let steps = object["steps"] as? [[String: String]] ?? []

        #expect(steps.contains { $0["action"] == "move" && ($0["to"]?.contains("/skills/seo") ?? false) })
        #expect(steps.contains { $0["action"] == "replace-symlink-with-directory" })
        #expect(steps.contains { $0["action"] == "symlink" })
        #expect(steps.contains { $0["action"] == "hardlink" })
    }

    @Test("Running it twice is a no-op the second time")
    func isIdempotent() throws {
        let f = try aliasedFixture()
        try f.makeSkill("seo", in: f.env.sharedAgentsSkillsDir)
        try f.makeAgentFile("seo-geo", in: f.env.claudeAgentsDir)

        try f.store.consolidation.apply(f.store.consolidation.plan())
        let second = f.store.consolidation.plan()
        #expect(second.isEmpty)
        #expect(second.blocked.isEmpty)
    }
}
