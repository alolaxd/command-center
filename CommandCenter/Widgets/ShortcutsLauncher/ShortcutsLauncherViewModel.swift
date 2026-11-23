import Foundation

@MainActor @Observable
final class ShortcutsLauncherViewModel {
    var items: [LauncherItem] = []
    var running: Set<String> = []
    var lastOutput: String?
    var systemShortcuts: [String] = []

    func load() { items = ShortcutsStore.all() }

    func loadSystemShortcuts() async { systemShortcuts = await ShortcutsStore.systemShortcuts() }

    func run(_ i: LauncherItem) async {
        running.insert(i.id)
        let (ok, out) = await ShortcutsStore.run(i)
        running.remove(i.id)
        lastOutput = out.isEmpty ? nil : "\(i.label): \(out.prefix(300))"
        WidgetBus.shared.toast(ok ? "Ran \(i.label)" : "\(i.label) failed", symbol: ok ? "checkmark.circle" : "exclamationmark.triangle")
    }

    func move(_ id: String, before target: String) {
        var ids = items.map(\.id)
        guard let from = ids.firstIndex(of: id), id != target else { return }
        ids.remove(at: from)
        ids.insert(id, at: ids.firstIndex(of: target) ?? ids.count)
        ShortcutsStore.reorder(ids)
        load()
    }
}
