import CryptoKit
import Foundation

/// Terminal pane layout persists in the widget configuration; live PTYs live in TerminalManager
/// keyed by the pane IDs, so they survive workspace switches and widget re-renders.
@MainActor
enum TerminalPanesStore {
    /// Sessions are keyed by (widget instance, pane) so two Terminal widgets created from the same
    /// default/preset configuration never share a shell.
    static func key(_ pane: TerminalPane, instance: UUID) -> UUID {
        let digest = SHA256.hash(data: Data((instance.uuidString + pane.id.uuidString).utf8))
        let b = Array(digest.prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }

    static func session(for pane: TerminalPane, instance: UUID) -> TerminalSession {
        TerminalManager.shared.session(for: key(pane, instance: instance), cwd: pane.cwd.isEmpty ? nil : (pane.cwd as NSString).expandingTildeInPath)
    }

    static func close(_ pane: TerminalPane, instance: UUID) { TerminalManager.shared.close(key(pane, instance: instance)) }
}

/// ⌘⇧T: add a tab to the first Terminal Panes widget (adding the widget if needed).
enum TerminalPanesCommands {
    @MainActor static func newTab() {
        let store = WorkspaceStore.shared
        if store.focusFirst(kind: TerminalPanesWidget.kind) == nil { store.addWidget(kind: TerminalPanesWidget.kind) }
        WidgetBus.shared.publish(.dataChanged("terminal.newTab"))
    }
}
