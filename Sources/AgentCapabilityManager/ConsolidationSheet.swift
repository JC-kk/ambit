import SwiftUI
import ACMCore

/// Consolidation moves real files around, so it is always previewed and confirmed first.
struct ConsolidationSheet: View {
    @Bindable var model: InventoryModel
    @Environment(\.dismiss) private var dismiss

    private var plan: ConsolidationService.Plan { model.consolidationPlan ?? .init() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Consolidate into the library", systemImage: "tray.and.arrow.down")
                .font(.headline)
            Text("Each source below moves into \(model.libraryPath) and is linked straight back. Nothing changes about what Claude and Codex can see today — the switches simply start working.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Metrics.gutter)
    }

    @ViewBuilder
    private var content: some View {
        if plan.isEmpty {
            ContentUnavailableView(
                "Nothing left to move",
                systemImage: "checkmark.circle",
                description: Text("Every skill and subagent already has its only copy in the library.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List {
                if plan.replacesClaudeSkillsSymlink {
                    Section("Directory change") {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("~/.claude/skills becomes a real directory")
                                Text("It is a symlink to \(plan.claudeSkillsSymlinkTarget?.path.abbreviatingHomeForDisplay ?? "another folder"), which Codex also scans. That is what makes the two columns move together.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } icon: {
                            Image(systemName: "folder.badge.gearshape").foregroundStyle(Palette.attention)
                        }
                    }
                }

                ForEach(CapabilityKind.allCases, id: \.self) { kind in
                    let moves = plan.moves(kind)
                    if !moves.isEmpty {
                        Section("\(kind.displayName) (\(moves.count))") {
                            ForEach(moves) { move in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(move.name).font(.identifier)
                                        Text(move.source.path.abbreviatingHomeForDisplay)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                    Spacer()
                                    if !move.parked.isEmpty {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 9))
                                            .foregroundStyle(Palette.attention)
                                            .help("\(move.parked.count) duplicate copy will be parked under backups/, not deleted")
                                    }
                                    ForEach(move.relinkTo, id: \.self) { AgentMark(agent: $0, size: 15) }
                                }
                            }
                        }
                    }
                }

                if !plan.blocked.isEmpty {
                    Section("Left alone") {
                        ForEach(plan.blocked, id: \.self) { reason in
                            Label(reason, systemImage: "hand.raised")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack {
            Text("Nothing is deleted. Every move is recorded in a manifest under backups/.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Consolidate") {
                model.applyConsolidation()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(plan.isEmpty)
        }
        .padding(18)
    }
}
