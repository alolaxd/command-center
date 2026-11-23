import Foundation

/// Terminal pane layout persists in the widget configuration; live PTYs live in TerminalManager
/// keyed by the pane IDs, so they survive workspace switches and widget re-renders.
@MainActor
enum TerminalPanesStore {
    static func session(for pane: TerminalPane) -> TerminalSession {
        TerminalManager.shared.session(for: pane.id, cwd: pane.cwd.isEmpty ? nil : (pane.cwd as NSString).expandingTildeInPath)
    }

    static func close(_ pane: TerminalPane) { TerminalManager.shared.close(pane.id) }
}

/// ⌘⇧T: add a tab to the first Terminal Panes widget (adding the widget if needed).
enum TerminalPanesCommands {
    @MainActor static func newTab() {
        let store = WorkspaceStore.shared
        if store.focusFirst(kind: TerminalPanesWidget.kind) == nil { store.addWidget(kind: TerminalPanesWidget.kind) }
        WidgetBus.shared.publish(.dataChanged("terminal.newTab"))
    }
}
