import Foundation
import AmbitCore

/// `Ambit --print` renders the same matrix the window shows, without opening a
/// window. Read-only: it scans and prints, and never writes to the library or to either agent.
enum TextReport {
    /// `--consolidate` prints the plan. It only carries it out when `--yes` is also given, so the
    /// destructive step can never happen by typing the wrong thing once.
    static func consolidate(apply: Bool) {
        let store = CapabilityStore()
        try? store.prepareLibrary()
        let plan = store.consolidation.plan()

        print("Library: \(store.env.library.path)\n")
        guard !plan.isEmpty else {
            print("Nothing to move — every skill and subagent already has its only copy in the library.")
            for reason in plan.blocked { print("  left alone: \(reason)") }
            return
        }

        if plan.replacesClaudeSkillsSymlink {
            print("~/.claude/skills becomes a real directory")
            print("  (currently a symlink to \(plan.claudeSkillsSymlinkTarget?.path ?? "?"), which Codex also scans)\n")
        }
        for kind in CapabilityKind.allCases {
            let moves = plan.moves(kind)
            guard !moves.isEmpty else { continue }
            print("\(kind.displayName) (\(moves.count))")
            for move in moves {
                let agents = move.relinkTo.map(\.displayName).joined(separator: "+")
                let dupes = move.parked.isEmpty ? "" : "  [\(move.parked.count) duplicate parked]"
                print("  \(move.name.padded(to: 26))\(agents)\(dupes)")
            }
            print("")
        }
        for reason in plan.blocked { print("  left alone: \(reason)") }

        guard apply else {
            print("\nDry run. Re-run with --consolidate --yes to carry this out.")
            return
        }
        do {
            let manifest = try store.consolidation.apply(plan)
            print("\nDone. Manifest: \(manifest.path)")
        } catch {
            print("\nStopped: \(error.localizedDescription)")
            print("Anything already moved is listed in the manifest under backups/.")
        }
    }

    static func run() {
        let store = CapabilityStore()
        let inventory = store.scan()

        print("Home: \(store.env.home.path)\n")

        for kind in CapabilityKind.allCases {
            let rows = inventory.of(kind)
            print(kind.displayName)
            print(String(repeating: "─", count: 62))
            guard !rows.isEmpty else {
                print("  (none)\n")
                continue
            }
            let width = max(24, rows.map(\.name.count).max() ?? 24)
            print("  " + "".padded(to: width) + AgentKind.allCases.map { $0.displayName.padded(to: 12) }.joined())
            for row in rows {
                let cells = AgentKind.allCases.map { row.exposure($0).status.label.padded(to: 12) }.joined()
                print("  " + row.name.padded(to: width) + cells)
            }
            print("")
        }

        guard !inventory.diagnostics.isEmpty else { return }
        print("Diagnostics")
        print(String(repeating: "─", count: 62))
        for diagnostic in inventory.diagnostics {
            print("  [\(diagnostic.severity.rawValue)] \(diagnostic.message)\n")
        }
    }
}

private extension String {
    func padded(to width: Int) -> String {
        count >= width ? self + "  " : self + String(repeating: " ", count: width - count)
    }
}
