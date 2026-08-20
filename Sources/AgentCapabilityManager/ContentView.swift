import SwiftUI
import ACMCore

struct ContentView: View {
    @Bindable var model: InventoryModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(model.title)
        .navigationSubtitle(model.subtitle)
        .searchable(text: $model.search, placement: .toolbar, prompt: model.searchPrompt)
        .toolbar { toolbar }
        .sheet(isPresented: $model.isShowingConsolidation) {
            ConsolidationSheet(model: model)
        }
        .alert(
            model.alert?.title ?? "",
            isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
        ) {
            Button("OK") { model.alert = nil }
        } message: {
            Text(model.alert?.message ?? "")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { model.sidebarSelection }, set: { model.sidebarSelection = $0 })) {
            Section("Capabilities") {
                ForEach(CapabilityKind.allCases, id: \.self) { kind in
                    Label {
                        HStack {
                            Text(kind.displayName)
                            Spacer()
                            Text("\(model.inventory.of(kind).count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    } icon: {
                        Image(systemName: kind.symbolName)
                    }
                    .tag(InventoryModel.SidebarItem.kind(kind))
                }
            }

            // Selectable: picking an agent shows everything that agent can load, across all kinds.
            Section("Agents") {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    HStack(spacing: 8) {
                        AgentMark(agent: agent, size: 18)
                        Text(agent.displayName)
                        Spacer()
                        Text("\(model.totalOnCount(agent))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(agent.tint)
                    }
                    .padding(.vertical, 1)
                    .tag(InventoryModel.SidebarItem.agent(agent))
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 178, ideal: 196, max: 240)
    }

    // MARK: - Detail

    private var detail: some View {
        VStack(spacing: 0) {
            if !model.diagnostics.isEmpty {
                DiagnosticsCard(
                    diagnostics: model.diagnostics,
                    showsDismiss: model.hasMissingSources,
                    onConsolidate: { model.beginConsolidation() },
                    onDismiss: { model.forgetMissingSources() }
                )
            }
            if let agent = model.focusedAgent {
                AgentInventoryView(agent: agent, model: model)
            } else {
                matrix
            }
            footer
        }
        .frame(minWidth: 560, minHeight: 400)
    }

    /// Agent column headings, pinned inside the list. Floating them above it looked identical at
    /// rest but let scrolled rows draw over the labels.
    private var columnHeadings: some View {
        SectionStrip(symbol: model.currentKind.symbolName, title: model.currentKind.displayName.uppercased()) {
            HStack(spacing: Metrics.switchGap) {
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    HStack(spacing: 5) {
                        AgentMark(agent: agent, size: 16)
                        Text(agent.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: Metrics.switchWidth)
                }
            }
        }
        .listRowInsets(EdgeInsets())
    }

    @ViewBuilder
    private var matrix: some View {
        if model.rows.isEmpty {
            VStack(spacing: 0) {
                columnHeadings
                EmptyStateView(kind: model.currentKind, search: model.search)
            }
        } else {
            List(selection: $model.selection) {
                Section {
                    ForEach(model.rows) { capability in
                        HStack(spacing: 12) {
                            CapabilityLabel(capability: capability)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            SwitchBank(capability: capability, model: model)
                        }
                        .contentShape(.rect)
                        .contextMenu { RowMenu(capability: capability, model: model) }
                        .listRowInsets(EdgeInsets(top: 5, leading: Metrics.gutter,
                                                  bottom: 5, trailing: Metrics.gutter))
                        .listRowSeparator(.hidden)
                    }
                } header: {
                    columnHeadings
                }
            }
            .listStyle(.inset)
            .environment(\.defaultMinListHeaderHeight, 0)
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(model.selectionSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Spacer(minLength: 12)

            if !model.selection.isEmpty {
                Text("Set to")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                ForEach(model.batchAgents, id: \.self) { agent in
                    HStack(spacing: 4) {
                        AgentMark(agent: agent, size: 15)
                        Button("On") { model.setSelected(true, agent: agent) }
                        Button("Off") { model.setSelected(false, agent: agent) }
                    }
                }
            }
        }
        .buttonStyle(.glass)
        .controlSize(.small)
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, 9)
        .frame(minHeight: 38)
        .animation(.snappy(duration: 0.18), value: model.selection.isEmpty)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                model.beginConsolidation()
            } label: {
                Label("Consolidate", systemImage: "tray.and.arrow.down")
            }
            .help("Move every remaining source into the library and link it back")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.revealLibrary()
            } label: {
                Label("Library", systemImage: "folder")
            }
            .help("Show the library in Finder")

            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Re-read the filesystem and both agents' configs")
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

// MARK: - Shared pieces

struct RowMenu: View {
    let capability: Capability
    var model: InventoryModel

    var body: some View {
        if let path = capability.primarySource {
            Button("Show in Finder") { model.reveal(path) }
            Button("Copy Source Path") { model.copyPath(path) }
            Divider()
            Text(path.path.abbreviatingHomeForDisplay)
        }
        if model.canAdopt(capability) {
            Divider()
            Button("Adopt into Library") { model.adopt(capability) }
        }
    }
}

private struct DiagnosticsCard: View {
    let diagnostics: [Diagnostic]
    let showsDismiss: Bool
    let onConsolidate: () -> Void
    let onDismiss: () -> Void

    private var needsConsolidation: Bool {
        diagnostics.contains { $0.id == "skills.claude-dir-is-codex-root" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(diagnostics) { diagnostic in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: diagnostic.severity == .warning
                          ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(diagnostic.severity == .warning ? Palette.attention : .secondary)
                    Text(diagnostic.message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            if needsConsolidation || showsDismiss {
                HStack(spacing: 8) {
                    if needsConsolidation {
                        Button("Consolidate to fix this", action: onConsolidate)
                    }
                    if showsDismiss {
                        Button("Stop tracking the missing source", action: onDismiss)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.attention.opacity(0.09), in: .rect(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.attention.opacity(0.22), lineWidth: 0.8)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}

struct EmptyStateView: View {
    let kind: CapabilityKind
    let search: String

    var body: some View {
        ContentUnavailableView {
            Label(search.isEmpty ? "No \(kind.displayName.lowercased()) yet" : "No matches",
                  systemImage: kind.symbolName)
        } description: {
            Text(search.isEmpty
                 ? "Put sources in the library, or run Consolidate to move in what Claude and Codex already have."
                 : "Nothing matches “\(search)”.")
        }
        .frame(maxHeight: .infinity)
    }
}
