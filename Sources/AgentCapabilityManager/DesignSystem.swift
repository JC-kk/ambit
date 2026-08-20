import SwiftUI
import ACMCore

/// One rule holds the whole interface together: **saturated colour means agency.**
///
/// Clay is Claude, blue is Codex, and a control is tinted only when that agent is actually loading
/// the thing. Everything structural stays graphite. So the amount of clay on screen reads directly
/// as "how much Claude loads" without anyone having to parse a single label. Amber and red are the
/// only other colours, and they mean attention rather than agency — something is here that this app
/// did not put here, or something is broken.
enum Palette {
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let codex = Color(red: 0.36, green: 0.58, blue: 0.98)
    static let attention = Color.orange
    static let fault = Color.red
}

enum Metrics {
    /// Row gutter. Everything in the detail pane lines up on this.
    static let gutter: CGFloat = 18
    /// One agent's switch. Fixed so the switches read as columns down the list.
    static let switchWidth: CGFloat = 86
    static let switchHeight: CGFloat = 25
    static let switchGap: CGFloat = 10
    static let compactSwitchWidth: CGFloat = 62
    static let compactSwitchHeight: CGFloat = 21
}

extension Font {
    /// Row title.
    static let rowTitle = Font.system(size: 13, weight: .medium)
    /// Row detail — 11pt is the macOS caption size; 10 was below it and read as an afterthought.
    static let rowDetail = Font.system(size: 11)
    /// Uppercase section label.
    static let eyebrow = Font.system(size: 10, weight: .semibold)
    static let pill = Font.system(size: 10, weight: .semibold, design: .rounded)
    static let pillCompact = Font.system(size: 9, weight: .semibold, design: .rounded)
}

extension AgentKind {
    /// Our own marks. Anthropic's and OpenAI's logos are trademarks we have no licence to redraw,
    /// and a wrong-looking copy would read worse than an honest glyph anyway.
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
    /// `nil` means "take the agent's tint" — the only place agency colour comes from.
    var fixedTint: Color? {
        switch self {
        case .on: nil
        case .off: nil
        case .external: Palette.attention
        case .broken: Palette.fault
        case .unsupported: nil
        }
    }

    func tint(for agent: AgentKind) -> Color {
        fixedTint ?? (self == .on ? agent.tint : .secondary)
    }

    var symbolName: String {
        switch self {
        case .on: "checkmark"
        case .off: "circle"
        case .external: "link"
        case .broken: "exclamationmark.triangle.fill"
        case .unsupported: "minus"
        }
    }

    /// Only ON is filled. Everything else is an outline, so a glance down a column counts loads.
    var isFilled: Bool { self == .on }
}

/// A small tinted tile carrying an agent's glyph.
struct AgentMark: View {
    let agent: AgentKind
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
            .fill(agent.tint.opacity(0.20))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                    .strokeBorder(agent.tint.opacity(0.40), lineWidth: 0.8)
            }
            .overlay {
                Image(systemName: agent.symbolName)
                    .font(.system(size: size * 0.50, weight: .semibold))
                    .foregroundStyle(agent.tint)
            }
            .frame(width: size, height: size)
            .accessibilityLabel(agent.displayName)
    }
}

/// An uppercase label strip. Opaque on purpose — a translucent strip lets scrolled rows bleed
/// through it, which is exactly the overlap this replaced.
struct SectionStrip<Trailing: View>: View {
    var symbol: String?
    var title: String
    var indent: CGFloat = Metrics.gutter
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            }
            Text(title)
                .font(.eyebrow)
                .tracking(0.6)
            Spacer(minLength: 8)
            trailing()
        }
        .foregroundStyle(.tertiary)
        .padding(.vertical, 6)
        .padding(.horizontal, indent)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

extension String {
    var abbreviatingHomeForDisplay: String {
        let home = NSHomeDirectory()
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }
}
