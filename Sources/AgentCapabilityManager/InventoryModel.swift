import AppKit
import Foundation
import Observation
import ACMCore

@MainActor
@Observable
final class InventoryModel {
    struct Alert: Equatable {
        var title: String
        var message: String
    }

    /// What the sidebar is pointing at: one capability kind (the matrix) or one agent (that
    /// agent's own inventory across all three kinds).
    enum SidebarItem: Hashable {
        case kind(CapabilityKind)
        case agent(AgentKind)
    }

    let store: CapabilityStore

    var inventory = Inventory()
    var selectedKind: CapabilityKind? = .skill
    /// Non-nil when the sidebar is focused on a single agent.
    var focusedAgent: AgentKind?
    var search = ""
    var selection = Set<String>()
    var alert: Alert?

    var isShowingConsolidation = false
    var consolidationPlan: ConsolidationService.Plan?

    init(store: CapabilityStore = CapabilityStore()) {
        self.store = store
        try? store.prepareLibrary()
        refresh()
    }

    // MARK: - Derived

    var currentKind: CapabilityKind { selectedKind ?? .skill }

    var sidebarSelection: SidebarItem? {
        get {
            if let focusedAgent { return .agent(focusedAgent) }
            return .kind(currentKind)
        }
        set {
            switch newValue {
            case .kind(let kind):
                selectedKind = kind
                focusedAgent = nil
            case .agent(let agent):
                focusedAgent = agent
            case nil:
                break
            }
            selection.removeAll()
        }
    }

    var rows: [Capability] { matching(inventory.of(currentKind)) }

    /// The focused agent's whole inventory, grouped by kind, in sidebar order.
    var agentSections: [(kind: CapabilityKind, rows: [Capability])] {
        CapabilityKind.allCases.compactMap { kind in
            let rows = matching(inventory.of(kind))
            return rows.isEmpty ? nil : (kind, rows)
        }
    }

    var agentRows: [Capability] { agentSections.flatMap(\.rows) }

    private func matching(_ capabilities: [Capability]) -> [Capability] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return capabilities }
        return capabilities.filter {
            $0.name.lowercased().contains(query) || ($0.summary?.lowercased().contains(query) ?? false)
        }
    }

    var diagnostics: [Diagnostic] { inventory.diagnostics }

    var libraryPath: String { store.env.library.path.abbreviatingHomeForDisplay }

    var title: String {
        focusedAgent?.displayName ?? currentKind.displayName
    }

    var subtitle: String {
        if let focusedAgent {
            let parts = CapabilityKind.allCases.map { kind in
                "\(kind.displayName) \(onCount(focusedAgent, in: kind))"
            }
            return "on: " + parts.joined(separator: " · ")
        }
        let counts = AgentKind.allCases.map { "\($0.displayName) \(onCount($0))" }.joined(separator: " · ")
        return "\(inventory.of(currentKind).count) · on: \(counts)"
    }

    var searchPrompt: String {
        focusedAgent == nil
            ? "Search \(currentKind.displayName.lowercased())"
            : "Search everything \(title) can load"
    }

    /// In an agent view only that agent's batch buttons make sense.
    var batchAgents: [AgentKind] {
        focusedAgent.map { [$0] } ?? AgentKind.allCases
    }

    var selectionSummary: String {
        let total = focusedAgent == nil ? rows.count : agentRows.count
        if selection.isEmpty {
            return "\(total) item\(total == 1 ? "" : "s") · select rows to change several at once"
        }
        return "\(selection.count) of \(total) selected"
    }

    var alertTitle: String { alert?.title ?? "" }

    func onCount(_ agent: AgentKind) -> Int {
        inventory.of(currentKind).count { $0.exposure(agent).status == .on }
    }

    func onCount(_ agent: AgentKind, in kind: CapabilityKind) -> Int {
        inventory.of(kind).count { $0.exposure(agent).status == .on }
    }

    /// Total across every kind — what the sidebar shows next to each agent.
    func totalOnCount(_ agent: AgentKind) -> Int {
        inventory.capabilities.count { $0.exposure(agent).status == .on }
    }

    // MARK: - Actions

    func refresh() {
        inventory = store.scan()
        selection.formIntersection(Set(inventory.capabilities.map(\.id)))
    }

    func toggle(_ capability: Capability, agent: AgentKind) {
        let exposure = capability.exposure(agent)
        guard exposure.canToggle else {
            alert = Alert(
                title: "\(capability.name) cannot be toggled for \(agent.displayName)",
                message: exposure.detail ?? "No mechanism is available."
            )
            return
        }
        perform("Nothing was changed") {
            try self.store.setEnabled(exposure.status != .on, capability: capability, agent: agent)
        }
    }

    /// Batch apply. One refusal does not abandon the rest — failures are collected and shown
    /// together so a mixed selection still does as much as it legitimately can.
    func setSelected(_ enabled: Bool, agent: AgentKind) {
        let visible = focusedAgent == nil ? rows : agentRows
        let targets = visible.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }

        var failures: [String] = []
        for capability in targets {
            let exposure = capability.exposure(agent)
            guard exposure.canToggle else {
                failures.append("\(capability.name): \(exposure.detail ?? "cannot be toggled")")
                continue
            }
            guard (exposure.status == .on) != enabled else { continue }
            do {
                try store.setEnabled(enabled, capability: capability, agent: agent)
            } catch {
                failures.append("\(capability.name): \(error.localizedDescription)")
            }
        }
        refresh()
        if !failures.isEmpty {
            alert = Alert(title: "Some items were left alone", message: failures.joined(separator: "\n\n"))
        }
    }

    func canAdopt(_ capability: Capability) -> Bool { store.canAdopt(capability) }

    var hasMissingSources: Bool {
        diagnostics.contains { $0.id == "library.source-missing" }
    }

    func forgetMissingSources() {
        store.forgetMissingSources()
        refresh()
    }

    func adopt(_ capability: Capability) {
        perform("Could not adopt \(capability.name)") { try self.store.adopt(capability) }
    }

    // MARK: - Consolidation

    func beginConsolidation() {
        consolidationPlan = store.consolidation.plan()
        isShowingConsolidation = true
    }

    func applyConsolidation() {
        guard let plan = consolidationPlan else { return }
        let moved = plan.moves.count
        do {
            let manifest = try store.consolidation.apply(plan)
            refresh()
            alert = Alert(
                title: "Consolidated",
                message: """
                \(moved) source\(moved == 1 ? "" : "s") now live only in \(libraryPath), linked back into each agent.

                A manifest of every move is at \(manifest.path.abbreviatingHomeForDisplay).
                """
            )
        } catch {
            refresh()
            alert = Alert(
                title: "Consolidation stopped",
                message: "\(error.localizedDescription)\n\nAnything already moved is recorded in the manifest under backups/."
            )
        }
        consolidationPlan = nil
    }

    // MARK: - Finder

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealLibrary() {
        NSWorkspace.shared.activateFileViewerSelecting([store.env.library])
    }

    func copyPath(_ url: URL?) {
        guard let url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    private func perform(_ failureTitle: String, _ work: () throws -> Void) {
        defer { refresh() }
        do {
            try work()
            alert = nil
        } catch {
            alert = Alert(title: failureTitle, message: error.localizedDescription)
        }
    }
}
