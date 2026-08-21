import Foundation

public enum AgentKind: String, CaseIterable, Sendable, Codable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }
}

public enum CapabilityKind: String, CaseIterable, Sendable, Codable {
    case skill
    case mcp
    case subagent

    public var displayName: String {
        switch self {
        case .skill: "Skills"
        case .mcp: "MCP"
        case .subagent: "Subagents"
        }
    }
}

public enum ExposureStatus: String, Sendable, Codable {
    /// Discoverable by this agent right now.
    case on
    /// Not discoverable, but a source exists that we could expose.
    case off
    /// Discoverable, but the on-disk entry is not managed by this app.
    case external
    /// Present but unusable — dangling link, missing SKILL.md, unparseable config.
    case broken
    /// This agent has no discovery mechanism for this capability kind.
    case unsupported

    public var label: String {
        switch self {
        case .on: "ON"
        case .off: "OFF"
        case .external: "EXTERNAL"
        case .broken: "BROKEN"
        case .unsupported: "N/A"
        }
    }
}

/// What we know about one capability as seen by one agent.
public struct AgentExposure: Sendable, Codable {
    public var status: ExposureStatus
    /// The entry inside the agent's discovery path, when one exists.
    public var exposurePath: URL?
    /// Why the status is what it is, and why a toggle may be refused. Shown in the UI.
    public var detail: String?
    /// False when the status cannot be changed from here (unsupported, forced-on, unowned entry).
    public var canToggle: Bool

    public init(status: ExposureStatus, exposurePath: URL? = nil, detail: String? = nil, canToggle: Bool) {
        self.status = status
        self.exposurePath = exposurePath
        self.detail = detail
        self.canToggle = canToggle
    }
}

public struct Capability: Sendable, Identifiable, Codable {
    public var kind: CapabilityKind
    public var name: String
    public var summary: String?
    /// The library copy, when this capability is managed by us.
    public var librarySource: URL?
    /// Best path to show and to reveal in Finder: the library copy if managed, else where it lives.
    public var primarySource: URL?
    public var exposures: [AgentKind: AgentExposure]

    public var id: String { "\(kind.rawValue):\(name)" }

    /// True when no library copy exists — i.e. the capability lives only in an agent's own directory.
    public var isExternalOnly: Bool { librarySource == nil }

    public func exposure(_ agent: AgentKind) -> AgentExposure {
        exposures[agent] ?? AgentExposure(status: .off, canToggle: false)
    }

    public init(
        kind: CapabilityKind,
        name: String,
        summary: String? = nil,
        librarySource: URL? = nil,
        primarySource: URL? = nil,
        exposures: [AgentKind: AgentExposure]
    ) {
        self.kind = kind
        self.name = name
        self.summary = summary
        self.librarySource = librarySource
        self.primarySource = primarySource
        self.exposures = exposures
    }
}

/// A machine-level problem worth telling the user about, surfaced above the matrix.
public struct Diagnostic: Sendable, Identifiable, Codable {
    public enum Severity: String, Sendable, Codable { case warning, info }
    public var id: String
    public var severity: Severity
    public var message: String

    public init(id: String, severity: Severity, message: String) {
        self.id = id
        self.severity = severity
        self.message = message
    }
}

public struct Inventory: Sendable, Codable {
    public var capabilities: [Capability]
    public var diagnostics: [Diagnostic]

    public init(capabilities: [Capability] = [], diagnostics: [Diagnostic] = []) {
        self.capabilities = capabilities
        self.diagnostics = diagnostics
    }

    public func of(_ kind: CapabilityKind) -> [Capability] {
        capabilities.filter { $0.kind == kind }.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

public enum SkillswitchError: LocalizedError {
    case refused(String)
    case io(String)
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case .refused(let m): m
        case .io(let m): m
        case .parse(let m): m
        }
    }
}
