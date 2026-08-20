import SwiftUI
import ACMCore

/// Two rules carry the whole interface.
///
/// **Saturated colour means agency.** Clay is Claude, blue is Codex, and a control is coloured only
/// when that agent is actually loading the thing. Amber and red are the only other colours and they
/// mean attention, not agency. So the amount of clay on screen answers "how much is Claude loading"
/// before anyone reads a word.
///
/// **Monospace means machine, sans means human.** Capability names *are* identifiers — `seo-technical`,
/// `ffmpeg-video-editor` — so they are set in mono along with every count and status. Descriptions and
/// explanations are prose and stay in the system face. The split is the app's whole subject: a bridge
/// between machine config and human intent.
enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.36, green: 0.58, blue: 0.98)
    static let attention = Color(red: 0.90, green: 0.62, blue: 0.24)
    static let fault = Color(red: 0.87, green: 0.36, blue: 0.34)

    /// Structural hairlines. Kept off `.separator` so the grid reads a touch quieter than a table.
    static let rule = Color.primary.opacity(0.10)
}

enum Metrics {
    static let gutter: CGFloat = 18
    static let rowSpacing: CGFloat = 12

    /// The switch itself, then the mono status word beside it.
    static let trackWidth: CGFloat = 30
    static let trackHeight: CGFloat = 17
    static let statusLabelWidth: CGFloat = 62
    static let switchGap: CGFloat = 14
    static var switchWidth: CGFloat { trackWidth + 7 + statusLabelWidth }

    static let compactTrackWidth: CGFloat = 24
    static let compactTrackHeight: CGFloat = 14
    static let compactLabelWidth: CGFloat = 44
    static var compactSwitchWidth: CGFloat { compactTrackWidth + 5 + compactLabelWidth }
}

extension Font {
    /// Capability names — identifiers, so mono.
    static let identifier = Font.system(size: 12.5, weight: .medium, design: .monospaced)
    static let identifierCompact = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// Human prose.
    static let prose = Font.system(size: 11)
    /// Uppercase structural label.
    static let eyebrow = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
    /// Status words and counts.
    static let status = Font.system(size: 9.5, weight: .semibold, design: .monospaced)
    static let statusCompact = Font.system(size: 9, weight: .semibold, design: .monospaced)
    static let counter = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}

extension AgentKind {
    /// Our own marks. Anthropic's and OpenAI's logos are trademarks we have no licence to redraw.
    var symbolName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Palette.claude
        case .codex: Palette.codex
        }
    }
}

extension CapabilityKind {
    var symbolName: String {
        switch self {
        case .skill: "wand.and.sparkles"
        case .mcp: "cable.connector"
        case .subagent: "person.2.badge.gearshape"
        }
    }
}

extension ExposureStatus {
    /// Where the knob sits. `nil` means there is no knob to draw.
    enum KnobPosition { case leading, trailing, middle }

    var knob: KnobPosition? {
        switch self {
        case .on: .trailing
        case .off: .leading
        case .external: .trailing   // it is on — just not by our hand
        case .broken: .middle
        case .unsupported: nil
        }
    }

    /// A dashed track means this app does not control the switch. Solid means it does.
    var isGoverned: Bool {
        switch self {
        case .on, .off: true
        case .external, .broken, .unsupported: false
        }
    }

    func tint(for agent: AgentKind) -> Color {
        switch self {
        case .on: agent.tint
        case .off: .secondary
        case .external: Palette.attention
        case .broken: Palette.fault
        case .unsupported: .secondary
        }
    }
}

/// A small tinted tile carrying an agent's glyph.
struct AgentMark: View {
    let agent: AgentKind
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(agent.tint.opacity(0.18))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(agent.tint.opacity(0.42), lineWidth: 0.8)
            }
            .overlay {
                Image(systemName: agent.symbolName)
                    .font(.system(size: size * 0.48, weight: .semibold))
                    .foregroundStyle(agent.tint)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(agent.displayName)
    }
}

/// An uppercase label strip. Solid rather than glass: content sits under it when scrolled, and a
/// translucent strip lets rows bleed through.
struct SectionStrip<Trailing: View>: View {
    var symbol: String?
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(title)
                .font(.eyebrow)
                .tracking(1.1)
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(.tertiary)
        .padding(.vertical, 7)
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
    }
}

/// A hairline running from the end of a name to the switch bank. In a matrix this is the device that
/// lets the eye travel along a row without losing it — the same reason a table of contents has one.
struct LeaderRule: View {
    var body: some View {
        Rectangle()
            .fill(Palette.rule)
            .frame(height: 1)
            .padding(.leading, 8)
    }
}

extension String {
    var abbreviatingHomeForDisplay: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
