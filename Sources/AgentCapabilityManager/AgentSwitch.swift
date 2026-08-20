import SwiftUI
import ACMCore

/// The signature control: an actual two-position switch, the same motif as the app icon.
///
/// The grammar carries real information rather than decorating the state. A **solid** track means
/// this app governs the switch; a **dashed** track means it does not, and no amount of clicking will
/// change that. The knob's position is on/off, and its colour is agency — the agent's own tint when
/// that agent is loading the thing, amber or red when something needs attention.
///
/// No glass here. The window and toolbar bring their own; piling it onto every control in the
/// content made the whole thing read as an effect rather than an instrument.
struct AgentSwitch: View {
    enum Size {
        case regular, compact

        var track: CGSize {
            self == .regular
                ? CGSize(width: Metrics.trackWidth, height: Metrics.trackHeight)
                : CGSize(width: Metrics.compactTrackWidth, height: Metrics.compactTrackHeight)
        }
        /// Clearance between the knob and the inside of the track, on every side.
        var knobInset: CGFloat {
            self == .regular ? Metrics.knobInset : Metrics.compactKnobInset
        }
        var labelWidth: CGFloat {
            self == .regular ? Metrics.statusLabelWidth : Metrics.compactLabelWidth
        }
        var gap: CGFloat { self == .regular ? 8 : 6 }
        var font: Font { self == .regular ? .status : .statusCompact }
    }

    let exposure: AgentExposure
    let agent: AgentKind
    var size: Size = .regular
    let action: () -> Void

    @State private var isHovering = false

    private var status: ExposureStatus { exposure.status }
    private var tint: Color { status.tint(for: agent) }
    private var isLive: Bool { exposure.canToggle }

    var body: some View {
        Button(action: action) {
            HStack(spacing: size.gap) {
                track
                Text(status.label)
                    .font(size.font)
                    .tracking(0.5)
                    .foregroundStyle(status == .off || status == .unsupported
                                     ? AnyShapeStyle(.tertiary) : AnyShapeStyle(tint))
                    .frame(width: size.labelWidth, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .opacity(isLive ? 1 : 0.65)
        .onHover { isHovering = $0 }
        .help(helpText)
        .accessibilityLabel("\(agent.displayName): \(status.label)")
    }

    private var track: some View {
        let track = size.track
        let inset = size.knobInset
        let knobDiameter = track.height - inset * 2

        return Capsule()
            .fill(status == .on ? tint.opacity(0.24) : Color.primary.opacity(0.055))
            .overlay {
                Capsule().strokeBorder(
                    tint.opacity(status == .on ? 0.55 : 0.28),
                    style: StrokeStyle(lineWidth: 1, dash: status.isGoverned ? [] : [2.2, 2.2])
                )
            }
            // Positioned by padding, so the clearance from the border is the inset by construction.
            // The previous version computed an offset that put the knob's edge exactly on the stroke.
            .overlay(alignment: alignment) {
                if status.knob != nil {
                    Circle()
                        .fill(tint.opacity(status == .off ? 0.6 : 1))
                        .frame(width: knobDiameter, height: knobDiameter)
                        .padding(inset)
                }
            }
            .frame(width: track.width, height: track.height)
            .scaleEffect(isHovering && isLive ? 1.06 : 1)
            .animation(.snappy(duration: 0.18), value: status)
            .animation(.snappy(duration: 0.14), value: isHovering)
    }

    private var alignment: Alignment {
        switch status.knob {
        case .leading: .leading
        case .trailing: .trailing
        case .middle, nil: .center
        }
    }

    private var helpText: String {
        var parts = ["\(agent.displayName): \(status.label)"]
        if let detail = exposure.detail { parts.append(detail) }
        if let path = exposure.exposurePath { parts.append(path.path.abbreviatingHomeForDisplay) }
        if !isLive, status != .unsupported {
            parts.append("Dashed means this app does not govern the switch — the reason is above.")
        }
        return parts.joined(separator: "\n\n")
    }
}

/// The pair of switches as a fixed-width bank, so they read as columns down the list.
struct SwitchBank: View {
    let capability: Capability
    var model: InventoryModel

    var body: some View {
        HStack(spacing: Metrics.switchGap) {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                AgentSwitch(exposure: capability.exposure(agent), agent: agent) {
                    model.toggle(capability, agent: agent)
                }
                .frame(width: Metrics.switchWidth, alignment: .leading)
            }
        }
    }
}

/// Identifier over prose, with an amber dot when the source is *not* in the library.
///
/// Badging the exception rather than the norm: once consolidated almost everything is managed, so
/// marking every managed row was noise that hid the handful that need attention.
struct CapabilityLabel: View {
    let capability: Capability
    var showsLeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(capability.name).font(.identifier)
                if capability.librarySource == nil {
                    Circle()
                        .fill(Palette.attention)
                        .frame(width: 4.5, height: 4.5)
                        .help("Source lives outside the library")
                }
                if showsLeader { LeaderRule() }
            }
            Text(detail)
                .font(.prose)
                .foregroundStyle(capability.summary?.isEmpty == false ? .secondary : .tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var detail: String {
        if let summary = capability.summary, !summary.isEmpty { return summary }
        return capability.primarySource?.path.abbreviatingHomeForDisplay ?? "No source on disk"
    }
}
