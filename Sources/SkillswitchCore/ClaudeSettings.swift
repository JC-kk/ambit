import Foundation

/// Reads and minimally edits `~/.claude/settings.json`.
///
/// Only `skillOverrides` is ever written. Everything else in the file is preserved byte-for-byte
/// in content by the round-trip guard in `JSONConfig.write`.
public enum ClaudeSettings {
    public static let overridesKey = "skillOverrides"

    public static func skillOverrides(env: SkillswitchEnvironment) -> [String: String] {
        let settings = (try? JSONConfig.read(env.claudeSettings)) ?? [:]
        guard let raw = settings[overridesKey] as? [String: Any] else { return [:] }
        return raw.compactMapValues { $0 as? String }
    }

    /// Sets `skillOverrides[name]`, or removes the entry when `value` is nil.
    public static func setSkillOverride(_ name: String, to value: String?, env: SkillswitchEnvironment) throws {
        let settings = (try? JSONConfig.read(env.claudeSettings)) ?? [:]
        var overrides = (settings[overridesKey] as? [String: Any]) ?? [:]

        if let value {
            if (overrides[name] as? String) == value { return }
            overrides[name] = value
        } else {
            if overrides[name] == nil { return }
            overrides.removeValue(forKey: name)
        }

        try JSONConfig.setTopLevelValue(
            overrides.isEmpty ? nil : overrides,
            forKey: overridesKey,
            in: env.claudeSettings,
            env: env
        )
    }
}
