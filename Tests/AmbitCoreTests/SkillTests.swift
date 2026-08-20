import Testing
import Foundation
@testable import AmbitCore

@Suite("Skills")
struct SkillTests {

    @Test("A library skill starts OFF everywhere and toggles independently per agent")
    func independentToggles() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("seo")

        #expect(try f.status(.skill, "seo", .claude) == .off)
        #expect(try f.status(.skill, "seo", .codex) == .off)

        try f.store.skills.setEnabled(true, name: "seo", agent: .claude)
        #expect(try f.status(.skill, "seo", .claude) == .on)
        #expect(try f.status(.skill, "seo", .codex) == .off)

        try f.store.skills.setEnabled(true, name: "seo", agent: .codex)
        #expect(try f.status(.skill, "seo", .codex) == .on)

        try f.store.skills.setEnabled(false, name: "seo", agent: .codex)
        #expect(try f.status(.skill, "seo", .claude) == .on)
        #expect(try f.status(.skill, "seo", .codex) == .off)
    }

    @Test("Disabling removes only the symlink; the library source survives")
    func disableNeverDeletesSource() throws {
        let f = try Fixture()
        let source = try f.makeLibrarySkill("shopify")
        try f.store.skills.setEnabled(true, name: "shopify", agent: .claude)

        let link = f.env.claudeSkillsDir.appendingPathComponent("shopify")
        #expect(FileSafety.isSymlink(link))

        try f.store.skills.setEnabled(false, name: "shopify", agent: .claude)
        #expect(!FileSafety.exists(link))
        #expect(FileSafety.exists(source.appendingPathComponent("SKILL.md")))
    }

    @Test("A real directory in the discovery path reads as EXTERNAL and is never deleted")
    func externalRealDirectoryIsNeverDeleted() throws {
        let f = try Fixture()
        try f.makeSkill("audio-research", in: f.env.claudeSkillsDir)
        try f.makeSkill("audio-research", in: f.env.codexSkillsDir)

        #expect(try f.status(.skill, "audio-research", .claude) == .external)
        #expect(try f.status(.skill, "audio-research", .codex) == .external)

        // Claude can hide it non-destructively; Codex has no such switch and must refuse.
        try f.store.skills.setEnabled(false, name: "audio-research", agent: .claude)
        #expect(try f.status(.skill, "audio-research", .claude) == .off)
        #expect(FileSafety.exists(f.env.claudeSkillsDir.appendingPathComponent("audio-research/SKILL.md")))
        #expect(ClaudeSettings.skillOverrides(env: f.env)["audio-research"] == "off")

        #expect(throws: AmbitError.self) {
            try f.store.skills.setEnabled(false, name: "audio-research", agent: .codex)
        }
        #expect(FileSafety.exists(f.env.codexSkillsDir.appendingPathComponent("audio-research/SKILL.md")))
    }

    @Test("Re-enabling a Claude skill clears the override")
    func reEnableClearsOverride() throws {
        let f = try Fixture()
        try f.makeSkill("geo", in: f.env.claudeSkillsDir)
        try f.store.skills.setEnabled(false, name: "geo", agent: .claude)
        #expect(ClaudeSettings.skillOverrides(env: f.env)["geo"] == "off")

        try f.store.skills.setEnabled(true, name: "geo", agent: .claude)
        #expect(ClaudeSettings.skillOverrides(env: f.env)["geo"] == nil)
        #expect(try f.status(.skill, "geo", .claude) == .external)
    }

    @Test("A symlink pointing outside the library is EXTERNAL and is never removed")
    func foreignSymlinkIsNeverRemoved() throws {
        let f = try Fixture()
        let elsewhere = try f.makeSkill("vendor", in: f.home.appendingPathComponent("vendor-skills"))
        let link = f.env.codexSkillsDir.appendingPathComponent("vendor")
        try FileSafety.createSymlink(at: link, target: elsewhere)

        #expect(try f.status(.skill, "vendor", .codex) == .external)
        #expect(throws: AmbitError.self) {
            try f.store.skills.setEnabled(false, name: "vendor", agent: .codex)
        }
        #expect(FileSafety.isSymlink(link))
    }

    @Test("A dangling managed symlink reads BROKEN and can be cleaned up")
    func brokenSymlink() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("ghost")
        try f.store.skills.setEnabled(true, name: "ghost", agent: .codex)
        try FileManager.default.removeItem(at: f.env.librarySkills.appendingPathComponent("ghost"))

        #expect(try f.status(.skill, "ghost", .codex) == .broken)
        try f.store.skills.setEnabled(false, name: "ghost", agent: .codex)
        #expect(!FileSafety.exists(f.env.codexSkillsDir.appendingPathComponent("ghost")))
    }

    @Test("Skills under ~/.agents/skills are reported as forced ON for Codex")
    func sharedAgentsRootForcesCodexOn() throws {
        let f = try Fixture()
        try f.makeSkill("forced", in: f.env.sharedAgentsSkillsDir)

        let capability = try f.capability(.skill, "forced")
        let codex = capability.exposure(.codex)
        #expect(codex.status == .external)
        #expect(codex.canToggle == false)
        #expect(codex.detail?.contains("~/.agents/skills") == true)
    }

    @Test("A symlinked ~/.claude/skills that is also a Codex root raises a diagnostic")
    func claudeSkillsDirAliasedToCodexRootIsReported() throws {
        let f = try Fixture()
        try FileManager.default.removeItem(at: f.env.claudeSkillsDir)
        try FileSafety.ensureDirectory(f.env.sharedAgentsSkillsDir)
        try FileSafety.createSymlink(at: f.env.claudeSkillsDir, target: f.env.sharedAgentsSkillsDir)
        try f.makeSkill("shared", in: f.env.sharedAgentsSkillsDir)

        let inventory = f.store.scan()
        #expect(inventory.diagnostics.contains { $0.id == "skills.claude-dir-is-codex-root" })
        let shared = inventory.of(.skill).first { $0.name == "shared" }
        #expect(shared?.exposure(.codex).canToggle == false)
    }

    @Test("Adopt copies into the library, parks the original and leaves a working symlink")
    func adoptIsReversible() throws {
        let f = try Fixture()
        try f.makeSkill("legacy", in: f.env.claudeSkillsDir, description: "Adopt me.")

        try f.store.skills.adopt(name: "legacy", from: .claude)

        let library = f.env.librarySkills.appendingPathComponent("legacy/SKILL.md")
        #expect(FileSafety.exists(library))
        #expect(FileSafety.isSymlink(f.env.claudeSkillsDir.appendingPathComponent("legacy")))
        #expect(try f.status(.skill, "legacy", .claude) == .on)

        // The pre-adopt directory is parked under backups/, not destroyed.
        let backups = FileSafety.directoryEntries(f.env.libraryBackups)
        #expect(backups.contains { $0.hasPrefix("adopted-") })

        // And it is now a normal managed skill.
        try f.store.skills.setEnabled(false, name: "legacy", agent: .claude)
        #expect(try f.status(.skill, "legacy", .claude) == .off)
        #expect(FileSafety.exists(library))
    }

    @Test("Enabling a skill with no library source is refused")
    func enableWithoutSourceRefused() throws {
        let f = try Fixture()
        #expect(throws: AmbitError.self) {
            try f.store.skills.setEnabled(true, name: "nope", agent: .claude)
        }
    }
}
