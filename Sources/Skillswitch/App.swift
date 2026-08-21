import SwiftUI
import SkillswitchCore

@main
struct SkillswitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = InventoryModel()

    init() {
        let arguments = CommandLine.arguments
        if arguments.contains("--print") {
            TextReport.run()
            exit(0)
        }
        if arguments.contains("--consolidate") {
            TextReport.consolidate(apply: arguments.contains("--yes"))
            exit(0)
        }
        // `--panel` opens the desktop panel straight away, for a Dock alias or a launcher entry.
        PanelPresenter.opensPanelAtLaunch = arguments.contains("--panel")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: model)
        } label: {
            // The launch hook lives on the label, not the popover: the label is instantiated as
            // soon as the status item appears, whereas the popover only appears once clicked.
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Skillswitch", id: PanelPresenter.windowID) {
            ContentView(model: model)
                .onAppear { PanelPresenter.panelDidOpen() }
                .onDisappear { PanelPresenter.panelDidClose() }
        }
        .defaultSize(width: 880, height: 600)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                ForEach(Array(CapabilityKind.allCases.enumerated()), id: \.element) { index, kind in
                    Button(kind.displayName) { model.selectedKind = kind }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                Button("Consolidate into Library…") { model.beginConsolidation() }
            }
        }
    }
}
