import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            _ = AppDatabase.shared
            if AppPaths.isRunningTests { return }   // tests drive services themselves
            StatusItemController.shared.install()
            NotchController.shared.install()
            GlobalHotkeys.shared.handler = { action in
                switch action {
                case .toggleTerminal: StatusItemController.shared.toggle(tab: .terminal)
                case .quickCapture: StatusItemController.shared.toggle(tab: .capture)
                case .askAI: StatusItemController.shared.toggle(tab: .ai)
                case .commandPalette: StatusItemController.shared.toggle(tab: .terminal, prefill: ">")
                }
            }
            GlobalHotkeys.shared.registerAll()
            ClipboardHistory.shared.start()
            BackgroundServices.start()
            Task { await AIService.shared.detectOllama() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainActor.assumeIsolated { AppState.openMainWindow() } }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// ⌘Q (or Dock → Quit) hides to the menu bar. Real quits: "Quit Completely", logout, restart, shutdown.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            if AppState.reallyQuit { return .terminateNow }
            if let event = NSAppleEventManager.shared().currentAppleEvent,
               event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil {
                return .terminateNow   // logout / restart / shutdown
            }
            AppState.hideToMenuBar()
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { WorkspaceStore.shared.saveNow() }
    }
}
