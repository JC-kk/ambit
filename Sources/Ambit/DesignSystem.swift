import AppKit
import SwiftUI
import AmbitCore

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
    ///
    /// `knobInset` is the gap between the knob and the inside of the track, and it is applied as
    /// padding rather than computed into an offset — that way the clearance is guaranteed by the
    /// layout instead of by arithmetic that can land the knob exactly on the border.
    static let trackWidth: CGFloat = 33
    static let trackHeight: CGFloat = 18
    static let knobInset: CGFloat = 3
    static let statusLabelWidth: CGFloat = 62
    static let switchGap: CGFloat = 14
    static var switchWidth: CGFloat { trackWidth + 8 + statusLabelWidth }

    /// The popover drops the status word: the switch already says on or off by knob position and
    /// colour, so spelling it out again cost 100pt that the identifiers needed. Only the states that
    /// need explaining keep a marker, and it is a glyph in a fixed slot so the columns stay aligned.
    static let compactTrackWidth: CGFloat = 27
    static let compactTrackHeight: CGFloat = 15
    static let compactKnobInset: CGFloat = 2.5
    static let compactGlyphSlot: CGFloat = 14
    static var compactSwitchWidth: CGFloat { compactTrackWidth + 4 + compactGlyphSlot }
}

/// The machine-facing typeface.
///
/// SF Mono is a fine face, but it is *the* system face, and the single biggest reason an app reads as
/// "an Apple app" is that every glyph on screen is Apple's. Swapping the machine layer to a
/// distinctive mono changes the character of the whole interface without touching a single control —
/// which is the point worth knowing: the ceiling here was never the framework.
///
/// Falls back to the system mono when the family is unavailable, so the app never renders in Helvetica
/// on a machine that does not have it.
enum Typeface {
    /// JetBrains Mono, SIL OFL 1.1 — redistributable, so it ships inside the bundle.
    static let monoFamily = "JetBrainsMonoNL Nerd Font"

    static var hasMono: Bool {
        NSFontManager.shared.availableFontFamilies.contains(monoFamily)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard hasMono else { return .system(size: size, weight: weight, design: .monospaced) }
        return .custom(monoFamily, fixedSize: size).weight(weight)
    }
}

extension Font {
    /// Capability names — identifiers, so mono.
    static let identifier = Typeface.mono(12.5, .medium)
    static let identifierCompact = Typeface.mono(11)
    /// Human prose stays in the system face: it is prose, not data.
    static let prose = Font.system(size: 11)
    /// Uppercase structural label.
    static let eyebrow = Typeface.mono(9.5, .semibold)
    /// Status words and counts.
    static let status = Typeface.mono(9.5, .semibold)
    static let statusCompact = Typeface.mono(9, .semibold)
    static let counter = Typeface.mono(10.5, .medium)
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

    /// Shown where there is no room to spell the state out. `nil` for on and off — the switch has
    /// already said those, and repeating them is what crowded out the identifiers.
    var attentionGlyph: String? {
        switch self {
        case .on, .off: nil
        case .external: "link"
        case .broken: "exclamationmark.triangle.fill"
        case .unsupported: "minus"
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
