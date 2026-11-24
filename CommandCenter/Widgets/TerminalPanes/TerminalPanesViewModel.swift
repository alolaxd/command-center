import AppKit
import Foundation

@MainActor @Observable
final class TerminalPanesViewModel {
    var search = ""
    var showSearch = false
    var focusedPane: UUID?
    var instanceID = UUID()

    func selectedTab(_ config: TerminalPanesConfiguration) -> TerminalTab? {
        config.tabs.first { $0.id == config.selected } ?? config.tabs.first
    }

    func newTab(_ config: TerminalPanesConfiguration, update: (TerminalPanesConfiguration) -> Void) {
        var c = config
        let tab = TerminalTab(panes: [TerminalPane(cwd: config.startDirectory)])
        c.tabs.append(tab)
        c.selected = tab.id
        update(c)
    }

    func closeTab(_ tab: TerminalTab, _ config: TerminalPanesConfiguration, update: (TerminalPanesConfiguration) -> Void) {
        tab.panes.forEach { TerminalPanesStore.close($0, instance: instanceID) }
        var c = config
        c.tabs.removeAll { $0.id == tab.id }
        if c.tabs.isEmpty { c.tabs = [TerminalTab(panes: [TerminalPane(cwd: config.startDirectory)])] }
        if c.selected == tab.id { c.selected = c.tabs.last?.id }
        update(c)
    }

    func split(_ dir: TerminalTab.Split, _ config: TerminalPanesConfiguration, update: (TerminalPanesConfiguration) -> Void) {
        var c = config
        guard let i = c.tabs.firstIndex(where: { $0.id == selectedTab(config)?.id }) else { return }
        if dir == .none {
            c.tabs[i].panes.dropFirst().forEach { TerminalPanesStore.close($0, instance: instanceID) }
            c.tabs[i].panes = Array(c.tabs[i].panes.prefix(1))
        } else if c.tabs[i].panes.count < 2 {
            let cwd = TerminalPanesStore.session(for: c.tabs[i].panes[0], instance: instanceID).cwd ?? config.startDirectory
            c.tabs[i].panes.append(TerminalPane(cwd: cwd))
        }
        c.tabs[i].split = dir
        update(c)
    }

    func activeSession(_ config: TerminalPanesConfiguration) -> TerminalSession? {
        guard let tab = selectedTab(config) else { return nil }
        let pane = tab.panes.first { $0.id == focusedPane } ?? tab.panes.first
        return pane.map { TerminalPanesStore.session(for: $0, instance: instanceID) }
    }

    func find(_ config: TerminalPanesConfiguration, backwards: Bool = false) {
        guard !search.isEmpty, let s = activeSession(config) else { return }
        if !s.find(search, backwards: backwards) { NSSound.beep() }
    }
}
