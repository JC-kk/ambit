import SwiftUI
import ACMCore

/// One agent's switch for one capability.
///
/// Only `ON` is filled, and it is filled in that agent's colour. Everything else is an outline in
/// graphite, amber or red. That way a glance down the column counts what is loaded without reading
/// a single word, and the two agents stay visually distinct even side by side.
struct StatusCell: View {
    enum Size {
        case regular, compact

        var width: CGFloat { self == .regular ? Metrics.switchWidth : Metrics.compactSwitchWidth }
        var height: CGFloat { self == .regular ? Metrics.switchHeight : Metrics.compactSwitchHeight }
        var font: Font { self == .regular ? .pill : .pillCompact }
        var glyph: CGFloat { self == .regular ? 8 : 7 }
    }

    let exposure: AgentExposure
    let agent: AgentKind
    var size: Size = .regular
    let action: () -> Void

    @State private var isHovering = false

    private var isLive: Bool { exposure.canToggle }
    private var tint: Color { exposure.status.tint(for: agent) }
    private var filled: Bool { exposure.status.isFilled }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: exposure.status.symbolName)
                    .font(.system(size: size.glyph, weight: .bold))
                Text(exposure.status.label)
                    .font(size.font)
            }
            .foregroundStyle(filled ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.85)))
            .frame(width: size.width, height: size.height)
            .glassEffect(.regular.tint(tint.opacity(filled ? 0.22 : 0.05)).interactive(isLive), in: .capsule)
            .overlay {
                // A hairline gives the outline states enough definition to read as controls.
                // Without it OFF dissolved into the row background.
                Capsule().strokeBorder(tint.opacity(filled ? 0.45 : 0.22), lineWidth: 0.8)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isLive)
        .opacity(isLive ? 1 : 0.5)
        .scaleEffect(isHovering && isLive ? 1.03 : 1)
        .animation(.snappy(duration: 0.15), value: isHovering)
        .animation(.snappy(duration: 0.2), value: exposure.status)
        .onHover { isHovering = $0 }
        .help(helpText)
        .accessibilityLabel("\(agent.displayName) \(exposure.status.label)")
    }

    private var helpText: String {
        var parts = ["\(agent.displayName): \(exposure.status.label)"]
        if let detail = exposure.detail { parts.append(detail) }
        if let path = exposure.exposurePath { parts.append(path.path.abbreviatingHomeForDisplay) }
        if !isLive, exposure.status != .unsupported {
            parts.append("This switch is disabled — the reason is above.")
        }
        return parts.joined(separator: "\n\n")
    }
}

/// The pair of switches, as a fixed-width bank so they line up as columns down a list.
struct SwitchBank: View {
    let capability: Capability
    var model: InventoryModel

    var body: some View {
        HStack(spacing: Metrics.switchGap) {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                StatusCell(exposure: capability.exposure(agent), agent: agent) {
                    model.toggle(capability, agent: agent)
                }
            }
        }
    }

    static var width: CGFloat {
        CGFloat(AgentKind.allCases.count) * Metrics.switchWidth
            + CGFloat(AgentKind.allCases.count - 1) * Metrics.switchGap
    }
}

/// Name over detail, with an amber dot when the source is *not* in the library.
///
/// Marking the exception rather than the norm: once consolidated almost everything is managed, so
/// badging every managed row was noise that hid the handful that actually need attention.
struct CapabilityLabel: View {
    let capability: Capability

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Text(capability.name).font(.rowTitle)
                if capability.librarySource == nil {
                    Circle()
                        .fill(Palette.attention)
                        .frame(width: 5, height: 5)
                        .help("Source lives outside the library")
                }
            }
            Text(detail)
                .font(.rowDetail)
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
