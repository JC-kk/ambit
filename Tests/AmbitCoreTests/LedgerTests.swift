import Testing
import Foundation
@testable import AmbitCore

@Suite("Source ledger")
struct LedgerTests {

    @Test("A library source that disappears is reported instead of silently dropped")
    func vanishedSourceIsReported() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("notes-wiki")
        try f.store.skills.setEnabled(true, name: "notes-wiki", agent: .claude)

        // First scan records it as managed.
        #expect(f.store.scan().diagnostics.isEmpty)

        // Something outside this app removes both the exposure and the library copy.
        try FileManager.default.removeItem(at: f.env.claudeSkillsDir.appendingPathComponent("notes-wiki"))
        try FileManager.default.removeItem(at: f.env.librarySkills.appendingPathComponent("notes-wiki"))

        let inventory = f.store.scan()
        #expect(inventory.of(.skill).isEmpty)
        let diagnostic = inventory.diagnostics.first { $0.id == "library.source-missing" }
        #expect(diagnostic != nil)
        #expect(diagnostic?.message.contains("notes-wiki") == true)
    }

    @Test("Dismissing stops the report, and it stays dismissed")
    func forgetClearsTheReport() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("gone")
        _ = f.store.scan()
        try FileManager.default.removeItem(at: f.env.librarySkills.appendingPathComponent("gone"))
        #expect(f.store.scan().diagnostics.contains { $0.id == "library.source-missing" })

        f.store.forgetMissingSources()
        #expect(f.store.scan().diagnostics.isEmpty)
        #expect(f.store.scan().diagnostics.isEmpty)
    }

    @Test("An external capability the user removes is not reported as a loss")
    func externalRemovalIsNotOurBusiness() throws {
        let f = try Fixture()
        try f.makeSkill("vendor", in: f.env.codexSkillsDir)
        _ = f.store.scan()

        try FileManager.default.removeItem(at: f.env.codexSkillsDir.appendingPathComponent("vendor"))
        #expect(f.store.scan().diagnostics.isEmpty)
    }

    @Test("The ledger records names only — never enabled state")
    func ledgerHoldsNamesOnly() throws {
        let f = try Fixture()
        try f.makeLibrarySkill("seo")
        try f.store.skills.setEnabled(true, name: "seo", agent: .claude)
        _ = f.store.scan()

        let text = try f.read(f.env.library.appendingPathComponent("index.json"))
        #expect(text.contains("seo"))
        #expect(!text.lowercased().contains("enabled"))
        #expect(!text.lowercased().contains("claude"))

        // Turning it off must not look like a loss.
        try f.store.skills.setEnabled(false, name: "seo", agent: .claude)
        #expect(f.store.scan().diagnostics.isEmpty)
    }
}
