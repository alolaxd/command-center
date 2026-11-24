import AppKit
import Observation

/// Ring of the last 50 clipboard text entries. Polls `changeCount` (cheap) every 0.75s.
@MainActor @Observable
final class ClipboardHistory {
    static let shared = ClipboardHistory()

    struct Entry: Identifiable, Hashable { let id = UUID(); let text: String; let date: Date; let sourceApp: String? }

    private(set) var entries: [Entry] = []
    @ObservationIgnored private var lastChange = NSPasteboard.general.changeCount
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ignoreNext = false
    let capacity = 50

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.75, repeats: true) { _ in Task { @MainActor in ClipboardHistory.shared.poll() } }
        t.tolerance = 0.4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        if ignoreNext { ignoreNext = false; return }
        // Respect password managers' "concealed" marker.
        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true { return }
        guard let text = pb.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        entries.removeAll { $0.text == text }
        let source = AppPaths.demoMode ? ["Safari", "Terminal", "Mail", "Xcode", "Notes"][entries.count % 5] : NSWorkspace.shared.frontmostApplication?.localizedName
        entries.insert(Entry(text: text, date: Date(), sourceApp: source), at: 0)
        if entries.count > capacity { entries.removeLast(entries.count - capacity) }
    }

    func copy(_ entry: Entry) {
        ignoreNext = false
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }

    /// Copies then synthesizes ⌘V into the previously frontmost app (requires Accessibility permission to paste).
    func paste(_ entry: Entry) {
        copy(entry)
        // The menu bar panel is non-activating, so the previously frontmost app still has focus.
        if NSApp.isActive { NSApp.hide(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let src = CGEventSource(stateID: .combinedSessionState)
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
            let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
            down?.flags = .maskCommand; up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
        }
    }

    func remove(_ entry: Entry) { entries.removeAll { $0.id == entry.id } }
    func clear() { entries.removeAll() }
}
