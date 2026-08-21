import Foundation
@testable import SkillswitchCore

/// A throwaway HOME. Every test runs entirely inside one of these — nothing here can reach the
/// real ~/.claude, ~/.codex or ~/.agents.
final class Fixture {
    let home: URL
    var env: SkillswitchEnvironment { SkillswitchEnvironment(home: home) }
    var store: CapabilityStore { CapabilityStore(env: env) }

    init() throws {
        home = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("skillswitch-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try store.prepareLibrary()
        for directory in [env.claudeSkillsDir, env.claudeAgentsDir, env.codexSkillsDir, env.codexAgentsDir] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: home) }

    @discardableResult
    func makeSkill(_ name: String, in directory: URL, description: String = "A test skill.") throws -> URL {
        let dir = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: \(description)\n---\n\nBody.\n"
            .write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        return dir
    }

    @discardableResult
    func makeLibrarySkill(_ name: String, description: String = "A test skill.") throws -> URL {
        try makeSkill(name, in: env.librarySkills, description: description)
    }

    @discardableResult
    func makeAgentFile(_ name: String, in directory: URL, description: String = "A test agent.") throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("\(name).md")
        try "---\nname: \(name)\ndescription: \(description)\n---\n\nYou are a test agent.\n"
            .write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func capability(_ kind: CapabilityKind, _ name: String) throws -> Capability {
        let inventory = store.scan()
        guard let match = inventory.capabilities.first(where: { $0.kind == kind && $0.name == name }) else {
            throw SkillswitchError.io("No \(kind.rawValue) named \(name) in the inventory.")
        }
        return match
    }

    func status(_ kind: CapabilityKind, _ name: String, _ agent: AgentKind) throws -> ExposureStatus {
        try capability(kind, name).exposure(agent).status
    }
}
