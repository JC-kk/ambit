import SwiftUI
import ACMCore

/// The other axis of the matrix: everything one agent can load, grouped by kind, with just that
/// agent's switch. Answers "what is Claude loading right now?" without reading three tabs and one
/// column each time.
struct AgentInventoryView: View {
    let agent: AgentKind
    @Bindable var model: InventoryModel

    private var counterpart: AgentKind? {
        AgentKind.allCases.first { $0 != agent }
    }

    var body: some View {
        let sections = model.agentSections
        // The agent strip sits above the list rather than inside it: an empty `Section` used only
        // to carry a header renders a stray blank row.
        VStack(spacing: 0) {
            heading
            if sections.isEmpty {
                EmptyStateView(kind: model.currentKind, search: model.search)
            } else {
                List(selection: $model.selection) {
                    ForEach(sections, id: \.kind) { section in
                        Section {
                            ForEach(section.rows) { capability in
                                row(capability)
                            }
                        } header: {
                            SectionStrip(symbol: section.kind.symbolName,
                                         title: section.kind.displayName.uppercased()) {
                                Text("\(model.onCount(agent, in: section.kind)) of \(section.rows.count) on")
                                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                            }
                            .listRowInsets(EdgeInsets())
                        }
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListHeaderHeight, 0)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var heading: some View {
        HStack(spacing: 8) {
            AgentMark(agent: agent, size: 17)
            Text("EVERYTHING \(agent.displayName.uppercased()) CAN LOAD")
                .font(.eyebrow)
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 8)
            Text("\(model.totalOnCount(agent)) on")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(agent.tint)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Metrics.gutter)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func row(_ capability: Capability) -> some View {
        HStack(spacing: 12) {
            CapabilityLabel(capability: capability)
                .frame(maxWidth: .infinity, alignment: .leading)

            // The other agent, read-only and dimmed. Focusing one agent should never hide what the
            // other is doing, or you flip a switch without knowing the whole picture.
            if let counterpart {
                HStack(spacing: 4) {
                    AgentMark(agent: counterpart, size: 13)
                    Text(capability.exposure(counterpart).status.label)
                        .font(.pillCompact)
                }
                .foregroundStyle(.tertiary)
                .frame(width: 72, alignment: .trailing)
                .help("\(counterpart.displayName): \(capability.exposure(counterpart).status.label)")
            }

            StatusCell(exposure: capability.exposure(agent), agent: agent) {
                model.toggle(capability, agent: agent)
            }
        }
        .contentShape(.rect)
        .contextMenu { RowMenu(capability: capability, model: model) }
        .listRowInsets(EdgeInsets(top: 5, leading: Metrics.gutter, bottom: 5, trailing: Metrics.gutter))
        .listRowSeparator(.hidden)
    }
}
