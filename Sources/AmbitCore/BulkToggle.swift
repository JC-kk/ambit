import Foundation

/// What a whole column of switches adds up to, so one control can stand for it.
///
/// Only rows this app actually governs are counted. Every kind has rows it cannot move — a skill
/// forced on by `~/.agents/skills`, an `EXTERNAL` entry we did not create, `N/A` where the agent has
/// no discovery mechanism at all — and folding those into the total would make a master switch that
/// can never read `allOn`, which is worse than no master switch.
public enum BulkState: String, Sendable, Equatable, Codable {
    case allOn
    case allOff
    case mixed
    /// Nothing here can be toggled from this app, so there is nothing for a master to do.
    case unavailable
}

extension Sequence<Capability> {
    /// The rows a master switch may act on for `agent`.
    public func togglable(for agent: AgentKind) -> [Capability] {
        filter { $0.exposure(agent).canToggle }
    }

    public func bulkState(for agent: AgentKind) -> BulkState {
        let governed = togglable(for: agent)
        guard !governed.isEmpty else { return .unavailable }
        let on = governed.count { $0.exposure(agent).status == .on }
        if on == 0 { return .allOff }
        if on == governed.count { return .allOn }
        return .mixed
    }
}
