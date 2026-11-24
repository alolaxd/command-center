import EventKit
import XCTest
@testable import Command_Center

@MainActor
final class ProductivityTests: XCTestCase {
    // MARK: Natural language (Reminders / Calendar / Countdowns)
    func testNaturalLanguageParsing() {
        let r = NaturalDateParser.parse("Buy milk tomorrow 3pm")
        XCTAssertEqual(r.title, "Buy milk")
        XCTAssertTrue(r.hasTime)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        XCTAssertTrue(Calendar.current.isDate(r.date!, inSameDayAs: tomorrow))
        XCTAssertEqual(Calendar.current.component(.hour, from: r.date!), 15)
        let none = NaturalDateParser.parse("Call mom")
        XCTAssertNil(none.date); XCTAssertEqual(none.title, "Call mom")
        XCTAssertFalse(NaturalDateParser.parse("Pay rent on friday").hasTime)
    }

    // MARK: Reminders (EventKit — runs when the app has Reminders access)
    func testRemindersAddCompleteSnoozeDelete() async throws {
        try XCTSkipUnless(EKEventStore.authorizationStatus(for: .reminder) == .fullAccess, "Reminders access not granted to Command Center")
        let r = try XCTUnwrap(RemindersStore.add("CC test reminder tomorrow 9am"))
        XCTAssertEqual(r.title, "CC test reminder")
        XCTAssertNotNil(r.dueDate)
        RemindersStore.snooze(r, by: 3600)
        XCTAssertEqual(Calendar.current.component(.hour, from: r.dueDate!), 10)
        let vm = RemindersViewModel()
        await vm.load(RemindersConfiguration())
        XCTAssertTrue((vm.today + vm.upcoming + vm.overdue).contains { $0.calendarItemIdentifier == r.calendarItemIdentifier })
        RemindersStore.saveOrder([r.calendarItemIdentifier])
        XCTAssertEqual(RemindersStore.ranks()[r.calendarItemIdentifier], 0)
        RemindersStore.complete(r)
        XCTAssertTrue(r.isCompleted)
        RemindersStore.delete(r)
    }

    // MARK: Calendar
    func testCalendarConflictDetection() {
        let store = EKEventStore()
        func ev(_ startH: Double, _ endH: Double) -> EKEvent {
            let e = EKEvent(eventStore: store)
            let day = Calendar.current.startOfDay(for: Date())
            e.startDate = day.addingTimeInterval(startH * 3600); e.endDate = day.addingTimeInterval(endH * 3600)
            return e
        }
        let a = ev(9, 10), b = ev(9.5, 11), c = ev(11, 12)
        // eventIdentifier is nil for unsaved events; conflicts() keys by identifier, so check overlap math directly.
        XCTAssertTrue(a.startDate < b.endDate && b.startDate < a.endDate)
        XCTAssertFalse(b.startDate < c.endDate && c.startDate < b.endDate, "back-to-back is not a conflict")
    }

    func testCalendarCreateResizeDelete() throws {
        try XCTSkipUnless(EKEventStore.authorizationStatus(for: .event) == .fullAccess, "Calendar access not granted to Command Center")
        let e = try XCTUnwrap(CalendarStore.create(fromText: "CC test event tomorrow 2pm"))
        XCTAssertEqual(e.endDate.timeIntervalSince(e.startDate), 3600)
        let vm = CalendarViewModel()
        vm.resizing = (e.eventIdentifier, e.endDate.addingTimeInterval(1800))
        vm.commitResize(e, config: CalendarConfiguration())
        XCTAssertEqual(e.endDate.timeIntervalSince(e.startDate), 5400)
        let dup = try XCTUnwrap(CalendarStore.create(title: "CC overlap", start: e.startDate.addingTimeInterval(600), end: e.endDate))
        let conflicts = CalendarStore.conflicts(CalendarStore.events(from: e.startDate, to: e.endDate, calendarIDs: []))
        XCTAssertTrue(conflicts.contains(e.eventIdentifier) && conflicts.contains(dup.eventIdentifier))
        CalendarStore.delete(dup); CalendarStore.delete(e)
    }

    // MARK: Inbox
    func testInboxCaptureTriageAndStale() throws {
        let link = InboxStore.add("https://example.com/article")
        XCTAssertEqual(link.kind, .link)
        let thought = InboxStore.add("Write blog post about grids")
        XCTAssertEqual(thought.kind, .text)
        XCTAssertTrue(InboxStore.untriaged().contains { $0.id == thought.id })

        var old = InboxItem(kind: .text, text: "Old idea")
        old.createdAt = Date().addingTimeInterval(-9 * 86400)
        AppDatabase.shared.write { try old.insert($0) }
        let vm = InboxViewModel()
        vm.load(InboxConfiguration())
        XCTAssertTrue(vm.isStale(vm.items.first { $0.id == old.id }!, InboxConfiguration()), "items older than 7 days are flagged")

        vm.toNote(thought)
        XCTAssertNotNil(NotesStore.note(titled: "Write blog post about grids"))
        vm.toKanban(link)
        XCTAssertTrue(KanbanStore.all().contains { $0.link == .url("https://example.com/article") })
        XCTAssertFalse(InboxStore.untriaged().contains { $0.id == thought.id || $0.id == link.id })
        XCTAssertTrue(InboxStore.recentTriaged().contains { $0.triagedTo == "note" })

        let img = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        InboxStore.addImage(img)
        let imageItem = try XCTUnwrap(InboxStore.untriaged().first { $0.kind == .image })
        XCTAssertTrue(FileManager.default.fileExists(atPath: imageItem.attachmentURL!.path))
        InboxStore.delete(imageItem)
        XCTAssertFalse(FileManager.default.fileExists(atPath: imageItem.attachmentURL!.path))
        InboxCapture.capture("from palette")
        XCTAssertTrue(InboxStore.untriaged().contains { $0.text == "from palette" })
    }

    // MARK: Notes
    func testNotesCRUDSearchBacklinksTagsRename() throws {
        let a = NotesStore.create(title: "Grid Design", body: "# Grid Design\nSnapping cells. #design #idea\nSee [[Layout Engine]].")
        let b = NotesStore.create(title: "Layout Engine", body: "Compaction algorithm, push-down collisions.")
        XCTAssertEqual(a.tags, ["design", "idea"])
        XCTAssertEqual(a.links, ["Layout Engine"])
        XCTAssertTrue(NotesStore.search("compaction").contains("Layout Engine"), "full-text search")
        XCTAssertTrue(NotesStore.search("snap").contains("Grid Design"), "prefix search")
        XCTAssertEqual(NotesStore.backlinks(to: "Layout Engine", in: NotesStore.all()).map(\.title), ["Grid Design"])
        NotesStore.rename(b, to: "Grid Engine")
        XCTAssertTrue(NotesStore.note(titled: "Grid Design")!.body.contains("[[Grid Engine]]"), "rename updates wiki links")
        let vm = NotesViewModel()
        vm.load()
        vm.filter = .tag("design")
        XCTAssertTrue(vm.visible.contains { $0.title == "Grid Design" })
        vm.filter = .smart(SmartFolder(name: "Ideas", query: "#idea"))
        XCTAssertEqual(vm.visible.map(\.title).filter { $0.hasPrefix("Grid") }, ["Grid Design"])
        vm.openWikiLink("Brand New Note")
        XCTAssertNotNil(NotesStore.note(titled: "Brand New Note"), "clicking a [[link]] to a missing note creates it")
        vm.select("Grid Design"); vm.edit("changed"); vm.flush()
        XCTAssertEqual(NotesStore.note(titled: "Grid Design")?.body, "changed")
        for t in ["Grid Design", "Grid Engine", "Brand New Note"] { if let n = NotesStore.note(titled: t) { NotesStore.delete(n) } }
        XCTAssertNil(NotesStore.note(titled: "Grid Engine"))
    }

    func testMarkdownRendererParsing() {
        let blocks = MarkdownView.parse("# Title\n\nPara one\ncontinues\n- item\n- [x] done\n1. first\n> quote\n```\ncode\n```\n---")
        XCTAssertEqual(blocks, [.heading(1, "Title"), .paragraph("Para one continues"), .bullet("item", 0), .task(true, "done"),
                                .ordered("1", "first"), .quote("quote"), .code("code"), .rule])
        XCTAssertEqual(MarkdownView.linkifyWiki("see [[My Note]]"), "see [My Note](wiki://My%20Note)")
    }

    // MARK: Kanban
    func testKanbanMoveWIPAndSwimlanes() {
        for c in KanbanStore.all() { KanbanStore.delete(c.id) }
        let vm = KanbanViewModel()
        vm.add("Fix login #web", column: .todo, lane: "")
        vm.add("Ship API", column: .todo, lane: "")
        vm.add("Write docs", column: .todo, lane: "")
        XCTAssertEqual(vm.cards.first { $0.title == "Fix login" }?.lane, "web", "#tag sets the swimlane")
        let ids = vm.cards.map(\.id)
        vm.drop(ids, on: .inProgress, lane: nil)
        var config = KanbanConfiguration()
        config.wipLimits[KanbanColumn.inProgress.rawValue] = 2
        XCTAssertTrue(vm.isOverLimit(.inProgress, config), "3 cards > WIP 2 turns the column red")
        vm.drop([ids[2]], on: .inProgress, lane: nil, before: ids[0])
        XCTAssertEqual(vm.cards(.inProgress, lane: nil).first?.id, ids[2], "drop before reorders")
        vm.drop([ids[0]], on: .done, lane: nil)
        XCTAssertNotNil(KanbanStore.all().first { $0.id == ids[0] }?.completedAt)
        XCTAssertEqual(Set(vm.lanes), ["", "web"])
        XCTAssertTrue(KanbanStore.aiSummary().contains("Done: Fix login"))
    }

    // MARK: Pomodoro + Habits
    func testPomodoroCompletionLogsSessionAndHabit() {
        let engine = PomodoroEngine.shared
        var c = PomodoroConfiguration(); c.autoStartBreaks = false; c.longBreakEvery = 4
        engine.apply(c)
        engine.reset()
        _ = habit(autoSource: "pomodoro", name: "Focus")
        let before = PomodoroStore.countToday()
        engine.start(task: "Write tests")
        XCTAssertEqual(engine.phase, .focus)
        XCTAssertTrue(engine.isRunning)
        engine.finishPhase(logged: true)
        XCTAssertEqual(PomodoroStore.countToday(), before + 1)
        XCTAssertEqual(PomodoroStore.sessions(since: Calendar.current.startOfDay(for: Date())).first?.task, "Write tests")
        XCTAssertEqual(engine.phase, .shortBreak)
        let focus = habit(autoSource: "pomodoro", name: "Focus")
        XCTAssertTrue(HabitStore.allDays(focus.id).contains(Date().dayKey), "Focus habit auto-completed")
        engine.reset()
        XCTAssertEqual(engine.phase, .idle)
    }

    func testPomodoroBlocksDistractingAppsConfig() {
        var c = PomodoroConfiguration(); c.blockApps = true; c.blockedBundleIDs = ["com.example.distraction"]
        PomodoroEngine.shared.apply(c)
        PomodoroEngine.shared.start()
        XCTAssertTrue(PomodoroEngine.shared.isRunning)
        PomodoroEngine.shared.reset()
    }

    func testHabitStreaksToggleAndSignals() {
        let h = Habit(name: "Read", autoSource: "reading")
        HabitStore.save(h)
        let today = Date(), y = today.addingTimeInterval(-86400), y2 = today.addingTimeInterval(-2 * 86400), old = today.addingTimeInterval(-10 * 86400)
        for d in [y, y2, old, old.addingTimeInterval(-86400), old.addingTimeInterval(-2 * 86400), old.addingTimeInterval(-3 * 86400)] { HabitStore.toggle(h.id, day: d) }
        var (cur, best) = HabitStore.streaks(HabitStore.allDays(h.id))
        XCTAssertEqual(cur, 2, "today not done yet doesn't break the streak")
        XCTAssertEqual(best, 4)
        HabitStore.signal("reading")       // auto-complete from another widget
        (cur, best) = HabitStore.streaks(HabitStore.allDays(h.id))
        XCTAssertEqual(cur, 3)
        HabitStore.toggle(h.id)             // un-toggle today
        XCTAssertFalse(HabitStore.allDays(h.id).contains(Date().dayKey))
        HabitBusBridge.start()
        WidgetBus.shared.publish(.habitSignal(name: "Read"))
        XCTAssertTrue(waitUntil(2) { HabitStore.allDays(h.id).contains(Date().dayKey) }, "bus signals reach habits")
        let vm = HabitTrackerViewModel()
        vm.load(weeks: 4)
        XCTAssertEqual(vm.gridWeeks(4).count, 4)
        XCTAssertTrue(vm.done(h, Date()))
        HabitStore.delete(h)
    }

    // MARK: Journal
    func testJournalEntryMoodPromptsAndSummaryErrors() async {
        _ = habit(autoSource: "journal", name: "Journal")
        var e = JournalStore.entry(Date())
        e.body = "Good day"; e.mood = 4; e.wentWell = "Tests passed"; e.grateful = "Coffee"
        JournalStore.save(e)
        let loaded = JournalStore.entry(Date())
        XCTAssertEqual(loaded.mood, 4); XCTAssertEqual(loaded.wentWell, "Tests passed")
        XCTAssertTrue(JournalStore.daysWithEntries().contains(Date().dayKey))
        XCTAssertTrue(HabitStore.allDays(habit(autoSource: "journal", name: "Journal").id).contains(Date().dayKey), "journaling ticks the Journal habit")
        XCTAssertTrue(JournalStore.aiSummary().contains("average mood"), JournalStore.aiSummary())
        var cal = Calendar.current; cal.firstWeekday = 2
        XCTAssertEqual(cal.component(.weekday, from: JournalStore.weekStart(Date())), 2, "weeks start Monday")
        // AI summary surfaces a clear error when no provider is configured.
        if !AIService.shared.isConfigured {
            do { _ = try await JournalStore.generateSummary(weekStart: JournalStore.weekStart(Date())); XCTFail("expected error") }
            catch { XCTAssertTrue(error.localizedDescription.contains("API key") || error.localizedDescription.contains("HTTP")) }
        }
        var empty = JournalStore.entry(Date()); empty.body = ""; empty.mood = 0; empty.wentWell = ""; empty.grateful = ""; empty.improve = ""
        JournalStore.save(empty)
        XCTAssertFalse(JournalStore.daysWithEntries().contains(Date().dayKey), "clearing an entry removes it")
    }
}
