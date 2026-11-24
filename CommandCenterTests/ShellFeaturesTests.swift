import AppKit
import XCTest
@testable import Command_Center

@MainActor
final class ShellFeaturesTests: XCTestCase {
    func testCommandPaletteCommands() async {
        XCTAssertEqual(CommandPalette.match("new reminder Buy milk")?.1, "Buy milk")
        XCTAssertEqual(CommandPalette.match("ask claude \"summarize my day\"")?.0.name, "ask")
        XCTAssertEqual(CommandPalette.match("ws Dev")?.0.name, "switch workspace")
        XCTAssertNil(CommandPalette.match("frobnicate"))
        XCTAssertTrue(CommandPalette.completions(for: ">sta").contains(">start pomodoro "))
        XCTAssertEqual(CommandPalette.completions(for: ">").count, CommandPalette.commands.count)

        let captured = await CommandPalette.execute("capture palette idea")
        XCTAssertTrue(InboxStore.untriaged().contains { $0.text == "palette idea" }, "palette said: \(captured); inbox: \(InboxStore.untriaged().map(\.text))")
        _ = await CommandPalette.execute("new card Palette card")
        XCTAssertTrue(KanbanStore.all().contains { $0.title == "Palette card" })
        _ = await CommandPalette.execute("new note Palette Note")
        XCTAssertNotNil(NotesStore.note(titled: "Palette Note"))
        let out = await CommandPalette.execute("start pomodoro palette task")
        XCTAssertTrue(out.contains("palette task")); PomodoroEngine.shared.reset()
        let store = WorkspaceStore.shared
        store.addWorkspace(name: "PaletteWS")
        store.select(index: 0)
        let switched = await CommandPalette.execute("switch workspace palettews")
        XCTAssertEqual(switched, "Switched to palettews")
        XCTAssertEqual(store.current?.name, "PaletteWS")
        let added = await CommandPalette.execute("add widget weather")
        XCTAssertTrue(added.contains("Weather"))
        XCTAssertEqual(store.current?.widgets.first?.kind, "weather")
        let logged = await CommandPalette.execute("log habit Focus")
        XCTAssertTrue(logged.contains("Logged"))
        let help = await CommandPalette.execute("help")
        XCTAssertTrue(help.contains(">new reminder"))
        if !AIService.shared.isConfigured {
            let unknown = await CommandPalette.execute("make me a sandwich")
            XCTAssertEqual(unknown, "Unknown command. Type >help")
        }
        store.deleteWorkspace(store.current!.id)
        if let n = NotesStore.note(titled: "Palette Note") { NotesStore.delete(n) }
    }

    func testClipboardHistoryRing() {
        let clip = ClipboardHistory.shared
        clip.clear()
        for i in 0..<55 {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("clip \(i)", forType: .string)
            clip.poll()
        }
        XCTAssertEqual(clip.entries.count, 50, "ring keeps the last 50")
        XCTAssertEqual(clip.entries.first?.text, "clip 54")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString("clip 10", forType: .string); clip.poll()
        XCTAssertEqual(clip.entries.first?.text, "clip 10"); XCTAssertEqual(clip.entries.filter { $0.text == "clip 10" }.count, 1, "deduplicated")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("hunter2", forType: .string)
        NSPasteboard.general.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        clip.poll()
        XCTAssertFalse(clip.entries.contains { $0.text == "hunter2" }, "password-manager copies are ignored")
        clip.copy(clip.entries[3])
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), clip.entries[3].text)
        clip.clear()
    }

    func testQuickTerminalAndHotkeys() {
        let q = TerminalManager.shared.quick
        XCTAssertTrue(q.isRunning)
        GlobalHotkeys.shared.setEnabled(.quickCapture, false)
        XCTAssertFalse(GlobalHotkeys.shared.isEnabled(.quickCapture))
        XCTAssertEqual(UserDefaults.standard.object(forKey: GlobalHotkeys.Action.quickCapture.defaultsKey) as? Bool, false)
        GlobalHotkeys.shared.setEnabled(.quickCapture, true)
    }

    func testCoalescedTickScheduler() {
        var a = 0, b = 0
        let t1 = TickScheduler.shared.subscribe(every: 1) { a += 1 }
        let t2 = TickScheduler.shared.subscribe(every: 2) { b += 1 }
        XCTAssertEqual(a, 1); XCTAssertEqual(b, 1, "fires immediately on subscribe")
        XCTAssertTrue(waitUntil(4) { a >= 3 })
        XCTAssertLessThan(b, a, "slower subscribers fire less often")
        TickScheduler.shared.unsubscribe(t1); TickScheduler.shared.unsubscribe(t2)
        let frozen = a
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(a, frozen, "unsubscribed callbacks stop")
    }

    func testWidgetBusDeliversEvents() {
        var got: String?
        let c = WidgetBus.shared.events.sink { if case .toast(let t, _) = $0 { got = t } }
        WidgetBus.shared.toast("hello bus")
        XCTAssertEqual(got, "hello bus")
        c.cancel()
    }

    func testHideToMenuBarKeepsAppRunning() {
        AppState.hideToMenuBar()
        XCTAssertEqual(NSApp.activationPolicy(), .accessory, "⌘Q hides to the menu bar instead of quitting")
        AppState.showInDock()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertFalse(AppState.reallyQuit)
    }
}

@MainActor
final class NotchTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testHardwareNotchGeometry() {
        // MacBook Pro 14": notch between the two auxiliary areas, 32pt tall.
        let n = NotchController.notch(screenFrame: screen, safeTop: 32,
                                      auxLeft: CGRect(x: 0, y: 950, width: 662, height: 32), auxRight: CGRect(x: 850, y: 950, width: 662, height: 32), menuBarHeight: 32)
        XCTAssertTrue(n.isHardware)
        XCTAssertEqual(n.rect, CGRect(x: 662, y: 950, width: 188, height: 32))
        XCTAssertEqual(NotchController.frame(for: .collapsed, notch: n, screenFrame: screen), n.rect, "collapsed island hides inside the notch")
        let live = NotchController.frame(for: .live, notch: n, screenFrame: screen)
        XCTAssertEqual(live.width, 188 + 2 * NotchController.liveWing); XCTAssertEqual(live.midX, n.rect.midX)
        let exp = NotchController.frame(for: .expanded, notch: n, screenFrame: screen)
        XCTAssertEqual(exp.maxY, screen.maxY, "grows downward from the top edge")
        XCTAssertEqual(exp.midX, n.rect.midX, accuracy: 0.5)
        XCTAssertEqual(exp.height, NotchController.expandedSize.height + 32)
    }

    func testVirtualNotchOnScreensWithoutOne() {
        let wide = CGRect(x: 0, y: 0, width: 1637, height: 1024)
        let n = NotchController.notch(screenFrame: wide, safeTop: 0, auxLeft: nil, auxRight: nil, menuBarHeight: 31)
        XCTAssertFalse(n.isHardware)
        XCTAssertEqual(n.rect.midX, wide.midX); XCTAssertEqual(n.rect.maxY, wide.maxY); XCTAssertEqual(n.rect.height, 31)
        // Expanded island stays fully on screen even on an off-centre secondary display.
        let side = CGRect(x: 1637, y: 0, width: 800, height: 600)
        let sn = NotchController.notch(screenFrame: side, safeTop: 0, auxLeft: nil, auxRight: nil, menuBarHeight: 24)
        let exp = NotchController.frame(for: .expanded, notch: sn, screenFrame: side)
        XCTAssertGreaterThanOrEqual(exp.minX, side.minX); XCTAssertLessThanOrEqual(exp.maxX, side.maxX)
    }

    func testIslandCanBeDisabledAndRoutesToggles() {
        let saved = NotchController.isEnabled
        defer { NotchController.isEnabled = saved }
        NotchController.isEnabled = true
        NotchController.shared.toggle(tab: .clipboard)
        XCTAssertEqual(NotchController.shared.mode, .expanded)
        XCTAssertEqual(StatusItemController.shared.model.tab, .clipboard)
        NotchController.shared.toggle(tab: nil)
        XCTAssertNotEqual(NotchController.shared.mode, .expanded, "same hotkey collapses it")
        NotchController.isEnabled = false
        XCTAssertEqual(NotchController.shared.mode, .hidden, "disabling removes the island entirely")
    }

    func testLiveActivityAppearsWithRunningPomodoro() {
        let saved = NotchController.isEnabled
        defer { NotchController.isEnabled = saved; PomodoroEngine.shared.reset() }
        NotchController.isEnabled = true
        NotchController.showLiveActivity = true
        PomodoroEngine.shared.start(task: "Island")
        NotchController.shared.refreshActivity()
        XCTAssertTrue(NotchController.shared.state.pomodoroRunning)
        XCTAssertEqual(NotchController.shared.mode, .live)
        PomodoroEngine.shared.reset()
        NotchController.shared.refreshActivity()
        if AgentActivity.runningCount() == 0 { XCTAssertEqual(NotchController.shared.mode, .collapsed) }
    }
}
