import SwiftUI
import AmbitCore

/// The menu bar popover: the same matrix, condensed to what is useful in a glance-and-flip.
///
/// The density work here is all about giving identifiers their room. Names are the one thing that
/// cannot be abbreviated — `seo-technical` and `seo-tactical` truncate to the same string — so the
/// switch columns give up their status words, the leader rule is dropped, and what is left goes to
/// the name. Consolidation, batch actions and Finder integration stay in the desktop panel: putting
/// them here would make this a worse copy of the window rather than a faster one.
struct MenuBarPanel: View {
    @Bindable var model: InventoryModel
    @Environment(\.openWindow) private var openWindow

    private static let version = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 0) {
            kindPicker
            filterField
            columnHeader
            rows
            footer
        }
        .frame(width: 340)
        .frame(minHeight: 300, maxHeight: 500)
    }

    // MARK: - Chrome

    private var kindPicker: some View {
        Picker("", selection: $model.selectedKind) {
            ForEach(CapabilityKind.allCases, id: \.self) { kind in
                Text(kind.displayName).tag(Optional(kind))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .onChange(of: model.selectedKind) { _, _ in model.focusedAgent = nil }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 9)
    }

    private var filterField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            TextField("Filter", text: $model.search)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !model.search.isEmpty {
                Button {
                    model.search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: .capsule)
        .overlay { Capsule().strokeBorder(Palette.rule, lineWidth: 1) }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Labels the switch columns *and* carries the counts, so the two floating numbers that used to
    /// sit beside the filter field now mean something.
    private var columnHeader: some View {
        HStack(spacing: 8) {
            if model.diagnostics.isEmpty {
                // Not the kind name — the picker above already said that. The count is the thing
                // that is not visible anywhere else.
                Text("\(model.rows.count) ITEM\(model.rows.count == 1 ? "" : "S")")
                    .font(.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(.tertiary)
                    .contentTransition(.numericText())
            } else {
                Button {
                    PanelPresenter.show(openWindow)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                        Text("\(model.diagnostics.count) NEED ATTENTION")
                            .font(.eyebrow)
                            .tracking(1.1)
                    }
                    .foregroundStyle(Palette.attention)
                }
                .buttonStyle(.plain)
                .help("Open the panel for details")
            }

            Spacer(minLength: 4)

            ForEach(AgentKind.allCases, id: \.self) { agent in
                HStack(spacing: 4) {
                    AgentMark(agent: agent, size: 13)
                    Text("\(model.onCount(agent))")
                        .font(.counter)
                        .foregroundStyle(agent.tint)
                        .contentTransition(.numericText())
                }
                .frame(width: Metrics.compactSwitchWidth, alignment: .leading)
                .help("\(agent.displayName) loads \(model.onCount(agent)) of these")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: 1) }
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        if model.rows.isEmpty {
            VStack(spacing: 3) {
                Text(model.search.isEmpty ? "Nothing here yet" : "No matches")
                    .font(.system(size: 12, weight: .medium))
                Text(model.search.isEmpty ? "Open the panel to consolidate." : "Try a different filter.")
                    .font(.prose)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 28)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    // Zebra rather than a leader rule. A short name like `dws` leaves a wide gap
                    // before its switches, and the eye needs something to follow across it — but a
                    // rule through a single-line row reads as a strikethrough. Banding ties both
                    // columns to the name at once and adds no graphic element.
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, capability in
                        row(capability)
                            .background(index.isMultiple(of: 2)
                                        ? Color.clear : Color.primary.opacity(0.035))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Without this the ScrollView keeps its ideal height of zero: the outer
            // `.frame(minHeight:)` stretches the popover but never forces a flexible child to grow.
            .frame(maxHeight: .infinity)
        }
    }

    private func row(_ capability: Capability) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(capability.name)
                    .font(.identifierCompact)
                    .lineLimit(1)
                    // Tail, never middle: these are identifiers, and a chewed-out middle makes two
                    // different names look the same.
                    .truncationMode(.tail)
                if capability.librarySource == nil {
                    Circle()
                        .fill(Palette.attention)
                        .frame(width: 4, height: 4)
                        .help("Source lives outside the library")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(AgentKind.allCases, id: \.self) { agent in
                AgentSwitch(exposure: capability.exposure(agent), agent: agent, size: .compact) {
                    model.toggle(capability, agent: agent)
                }
                .frame(width: Metrics.compactSwitchWidth, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .help(capability.summary ?? capability.name)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Text("v\(Self.version)")
                .font(Typeface.mono(9.5))
                .foregroundStyle(.tertiary)

            Spacer()

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Re-read the filesystem and both agents' configs")

            Button("Open Panel") { PanelPresenter.show(openWindow) }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Palette.rule).frame(height: 1) }
    }
}

/// The status item's glyph — two switches, the same mark as the app icon.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "switch.2")
            .onAppear {
                guard PanelPresenter.opensPanelAtLaunch else { return }
                PanelPresenter.opensPanelAtLaunch = false
                PanelPresenter.show(openWindow)
            }
    }
}
