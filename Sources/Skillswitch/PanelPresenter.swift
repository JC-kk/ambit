import AppKit
import SwiftUI

/// The app lives in the menu bar (`LSUIElement`), so it runs as an accessory and shows no Dock
/// icon. The desktop panel is still a real window: while one is open the app switches to a regular
/// activation policy so the window can take focus and carry its own toolbar, then drops back to
/// accessory once the last panel closes.
@MainActor
enum PanelPresenter {
    static let windowID = "panel"

    /// Set from the command line before any scene is built.
    nonisolated(unsafe) static var opensPanelAtLaunch = false

    static func panelDidOpen() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    static func show(_ openWindow: OpenWindowAction) {
        NSApp.setActivationPolicy(.regular)
        openWindow(id: windowID)
        NSApp.activate()
        // A window restored from a previous session can come back ordered behind everything else.
        DispatchQueue.main.async {
            panelWindows.first?.makeKeyAndOrderFront(nil)
        }
    }

    static func panelDidClose() {
        // Give AppKit a turn to actually tear the window down before counting what is left.
        DispatchQueue.main.async {
            guard panelWindows.isEmpty else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Real panels only — the menu bar popover is an `NSPanel` that cannot become main.
    private static var panelWindows: [NSWindow] {
        NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
    }
}

/// Starts the app as a menu bar accessory and keeps it alive when the panel is closed.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
