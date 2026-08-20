import SwiftUI
import ACMCore

/// The menu bar popover: the same matrix, condensed to what is useful in a glance-and-flip.
///
/// Pick a kind, filter, flip a switch. Consolidation, batch actions and Finder integration live in
/// the desktop panel — putting them here would make the popover a worse version of the window
/// instead of a faster one.
struct MenuBarPanel: View {
    @Bindable var model: InventoryModel
    @Environment(\.openWindow) private var openWindow

    private static let version = Bundle.main
        .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !model.diagnostics.isEmpty {
                notice
                Divider()
            }
            rows
            Divider()
            footer
        }
        .frame(width: 348)
        .frame(minHeight: 320, maxHeight: 520)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Picker("", selection: $model.selectedKind) {
                    ForEach(CapabilityKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(Optional(kind))
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: model.selectedKind) { _, _ in model.focusedAgent = nil }
            }

            HStack(spacing: 10) {
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
                .padding(.vertical, 5)
                .background(Color.primary.opacity(0.06), in: .capsule)
                .overlay { Capsule().strokeBorder(Palette.rule, lineWidth: 1) }

                // Live count per agent for the kind on screen: the popover's whole reason to exist.
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    HStack(spacing: 3) {
                        AgentMark(agent: agent, size: 14)
                        Text("\(model.onCount(agent))")
                            .font(.counter)
                            .foregroundStyle(agent.tint)
                            .contentTransition(.numericText())
                    }
                    .help("\(agent.displayName) loads \(model.onCount(agent)) of these")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 11)
        .padding(.bottom, 10)
    }

    private var notice: some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(Palette.attention)
            Text("\(model.diagnostics.count) thing\(model.diagnostics.count == 1 ? "" : "s") need attention")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Details") { PanelPresenter.show(openWindow) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.attention)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Palette.attention.opacity(0.10))
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        if model.rows.isEmpty {
            VStack(spacing: 3) {
                Text(model.search.isEmpty ? "Nothing here yet" : "No matches")
                    .font(.system(size: 12, weight: .medium))
                Text(model.search.isEmpty ? "Open the panel to consolidate." : "Try a different filter.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 28)
        } else {
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.rows) { capability in
                        HStack(spacing: 8) {
                            Text(capability.name)
                                .font(.identifierCompact)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            LeaderRule()
                            ForEach(AgentKind.allCases, id: \.self) { agent in
                                AgentSwitch(exposure: capability.exposure(agent),
                                            agent: agent, size: .compact) {
                                    model.toggle(capability, agent: agent)
                                }
                                .frame(width: Metrics.compactSwitchWidth, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .help(capability.summary ?? capability.name)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollBounceBehavior(.basedOnSize)
            // Without this the ScrollView keeps its ideal height of zero: the outer
            // `.frame(minHeight:)` stretches the popover but never forces a flexible child to grow.
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Re-read the filesystem and both agents' configs")

            Button("Open Panel") { PanelPresenter.show(openWindow) }

            Spacer()

            Text("v\(Self.version)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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
