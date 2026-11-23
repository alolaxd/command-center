import XCTest
@testable import Command_Center

@MainActor
final class LifestyleUtilityTests: XCTestCase {
    // MARK: Stocks & Crypto
    func testTickerQuotesAndAlerts() async throws {
        let key = "TEST>\(UUID().uuidString)"
        XCTAssertTrue(TickerStore.shouldFire(key)); XCTAssertFalse(TickerStore.shouldFire(key), "alerts fire once per day")
        try XCTSkipUnless(networkAvailable(), "offline")
        let q = await TickerStore.quote("AAPL", range: .day)
        XCTAssertGreaterThan(try XCTUnwrap(q, "Yahoo Finance quote").price, 0)
        let btc = await TickerStore.quote("crypto:bitcoin", range: .week)
        if let btc { XCTAssertGreaterThan(btc.price, 1000); XCTAssertGreaterThan(btc.series.count, 10) }
        let vm = TickerViewModel()
        var c = TickerConfiguration(); c.entries = [TickerEntry(symbol: "AAPL", holdings: 2)]
        await vm.refresh(c)
        XCTAssertEqual(vm.portfolioValue(c).value, (vm.quotes["AAPL"]?.price ?? 0) * 2, accuracy: 0.01)
    }

    // MARK: Budget
    func testBudgetQuickAddRecurringAndBreakdown() {
        XCTAssertNil(BudgetStore.quickAdd("coffee"), "must start with an amount")
        let t = BudgetStore.quickAdd("12.50 lunch dining")!
        XCTAssertEqual(t.amount, 12.5); XCTAssertEqual(t.category, "Dining"); XCTAssertEqual(t.note, "lunch")
        XCTAssertEqual(BudgetStore.quickAdd("-2000 salary")!.category, "Other")
        // Starts on the 1st two months ago → charges on the 1st of that month, last month and this month.
        let start = Calendar.current.date(byAdding: .month, value: -2, to: Calendar.current.dateInterval(of: .month, for: Date())!.start)!
        let r = RecurringExpense(amount: 9.99, category: "Subscriptions", dayOfMonth: 1, note: "Music", startDate: start)
        BudgetStore.save(r)
        BudgetStore.populateRecurring(); BudgetStore.populateRecurring()
        let all = AppDatabase.shared.read { try BudgetTransaction.filter(Column("recurringId") == r.id).fetchAll($0) } ?? []
        XCTAssertEqual(all.count, 3, "one per month for 3 months, idempotent")
        let vm = BudgetViewModel(); vm.load()
        XCTAssertGreaterThanOrEqual(vm.spent["Dining"] ?? 0, 12.5)
        XCTAssertTrue(vm.barRows.contains { $0.category == "Dining" && $0.kind == "Budget" && $0.amount == 200 })
        vm.shift(-1)
        XCTAssertTrue(vm.transactions.contains { $0.recurringId == r.id })
        BudgetStore.delete(r)
    }

    // MARK: Health
    func testHealthManualLogAndExportImport() async throws {
        HealthStore.add(.water, 250); HealthStore.add(.water, 250)
        let vm = HealthViewModel(); vm.load()
        XCTAssertGreaterThanOrEqual(vm.today[.water] ?? 0, 500)
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        let now = fmt.string(from: Date()), later = fmt.string(from: Date().addingTimeInterval(1800))
        let xml = """
        <?xml version="1.0"?><HealthData>
        <Record type="HKQuantityTypeIdentifierStepCount" value="4000" startDate="\(now)" endDate="\(now)"/>
        <Record type="HKQuantityTypeIdentifierStepCount" value="5000" startDate="\(now)" endDate="\(now)"/>
        <Record type="HKQuantityTypeIdentifierActiveEnergyBurned" value="320" startDate="\(now)" endDate="\(now)"/>
        <Record type="HKQuantityTypeIdentifierHeartRate" value="60" startDate="\(now)" endDate="\(now)"/>
        <Record type="HKQuantityTypeIdentifierHeartRate" value="80" startDate="\(now)" endDate="\(now)"/>
        <Record type="HKCategoryTypeIdentifierSleepAnalysis" value="HKCategoryValueSleepAnalysisAsleepCore" startDate="\(now)" endDate="\(later)"/>
        <Workout workoutActivityType="HKWorkoutActivityTypeRunning" startDate="\(now)" endDate="\(later)"/>
        </HealthData>
        """
        let file = tempDir().appendingPathComponent("export.xml")
        try xml.write(to: file, atomically: true, encoding: .utf8)
        let (days, err) = await HealthStore.importExport(file)
        XCTAssertNil(err); XCTAssertEqual(days, 1)
        vm.load()
        XCTAssertGreaterThanOrEqual(vm.today[.steps] ?? 0, 9000)
        XCTAssertEqual(vm.today[.heartRate] ?? 0, 70, accuracy: 0.1, "heart rate averaged")
        XCTAssertEqual(vm.today[.sleepHours] ?? 0, 0.5, accuracy: 0.01)
        let exercise = HabitStore.habits().first { $0.autoSource == "health.workout" }!
        XCTAssertTrue(HabitStore.allDays(exercise.id).contains(Date().dayKey), "workout auto-completes Exercise habit")
    }

    // MARK: Now Playing
    func testNowPlayingWhenNoPlayerRunning() async {
        if !MusicStore.isRunning(.music) && !MusicStore.isRunning(.spotify) {
            let info = await MusicStore.current()
            XCTAssertNil(info, "never launches a player implicitly")
        }
        MusicStore.recordPlay(NowPlayingInfo(source: .music, title: "Song", artist: "Band", album: "", duration: 100, position: 1, isPlaying: true))
        MusicStore.recordPlay(NowPlayingInfo(source: .music, title: "Song", artist: "Band", album: "", duration: 100, position: 5, isPlaying: true))
        XCTAssertEqual(MusicStore.history().filter { $0.title == "Song" }.count, 1, "repeated polls don't duplicate history")
    }

    // MARK: World Clocks
    func testWorldClocksOverlap() {
        let ny = WorldClocksStore.Zone(identifier: "America/New_York", label: ""), ldn = WorldClocksStore.Zone(identifier: "Europe/London", label: "")
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ldn.tz
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
        let hours = WorldClocksStore.overlap(zones: [ldn, ny], workStart: 9, workEnd: 18, reference: ldn.tz, on: wednesday)
        XCTAssertEqual(hours, [14, 15, 16, 17], "London 14–18 = New York 9–13")
        XCTAssertTrue(WorldClocksStore.search("Tokyo").contains("Asia/Tokyo"))
        XCTAssertEqual(ny.city, "New York")
        let vm = WorldClocksViewModel()
        XCTAssertFalse(vm.offset(ldn).isEmpty)
    }

    // MARK: Countdowns
    func testCountdownParseProgressAndMilestones() {
        let c = CountdownStore.parse("Product Launch in 12 days")!
        XCTAssertEqual(c.name, "Product Launch")
        XCTAssertEqual(c.remaining / 86400, 12, accuracy: 1, "12 days out (time of day depends on the parser)")
        XCTAssertNil(CountdownStore.parse("No date here"))
        var past = Countdown(name: "half", start: Date().addingTimeInterval(-50), target: Date().addingTimeInterval(50))
        XCTAssertEqual(past.progress, 0.5, accuracy: 0.05)
        past.target = Date().addingTimeInterval(-1)
        XCTAssertEqual(CountdownStore.format(past.remaining), "Done")
        XCTAssertEqual(CountdownStore.format(2 * 86400 + 4 * 3600 + 60), "2d 4h")
        CountdownStore.save(c)
        let vm = CountdownViewModel(); vm.load(CountdownConfiguration())
        XCTAssertTrue(vm.items.contains { $0.id == c.id })
        CountdownStore.delete(c)
    }

    // MARK: Screen Time
    func testScreenTimeAccounting() {
        let day = "1999-\(String(format: "%02d", Int.random(in: 1...12)))-\(String(format: "%02d", Int.random(in: 10...28)))-\(UUID().uuidString.prefix(4))"
        ScreenTimeStore.add(bundleId: "com.test.a", name: "A", seconds: 120, day: day)
        ScreenTimeStore.add(bundleId: "com.test.a", name: "A", seconds: 60, day: day)
        ScreenTimeStore.add(bundleId: "com.test.b", name: "B", seconds: 30, day: day)
        ScreenTimeStore.pickup(day: day); ScreenTimeStore.pickup(day: day)
        let u = ScreenTimeStore.usage(day: day)
        XCTAssertEqual(u.map(\.name), ["A", "B"]); XCTAssertEqual(u[0].seconds, 180)
        XCTAssertEqual(ScreenTimeStore.pickups(day: day), 2)
        ScreenTimeTracker.start()
        ScreenTimeTracker.flush()
        XCTAssertEqual(ScreenTimeStore.dailyTotals(days: 7).count, 7)
    }

    // MARK: Shortcuts Launcher
    func testLauncherRunsItemsAndReorders() async {
        let shell = LauncherItem(kind: .shell, label: "Echo", value: "echo launcher-ok")
        let (ok, out) = await ShortcutsStore.run(shell)
        XCTAssertTrue(ok); XCTAssertEqual(out, "launcher-ok")
        let (asOK, asOut) = await ShortcutsStore.run(LauncherItem(kind: .applescript, label: "AS", value: "return 6 * 7"))
        XCTAssertTrue(asOK); XCTAssertEqual(asOut, "42")
        let (badOK, _) = await ShortcutsStore.run(LauncherItem(kind: .shell, label: "Fail", value: "exit 3"))
        XCTAssertFalse(badOK)
        let names = await ShortcutsStore.systemShortcuts()
        XCTAssertNotNil(names)
        let vm = ShortcutsLauncherViewModel(); vm.load()
        XCTAssertGreaterThanOrEqual(vm.items.count, 3, "seeded examples")
        let last = vm.items.last!.id, first = vm.items.first!.id
        vm.move(last, before: first)
        XCTAssertEqual(vm.items.first?.id, last, "drag-and-drop reorder persists")
    }

    // MARK: Custom widgets
    func testCustomWidgetRuntimeSamplesErrorsAndSharing() throws {
        for (name, script) in CustomWidgetStore.samples {
            guard case .success = CustomWidgetStore.render(script, widgetID: "t") else { return XCTFail("sample \(name) failed") }
        }
        guard case .failure(.message(let m)) = CustomWidgetStore.render("function render( {", widgetID: "t") else { return XCTFail() }
        XCTAssertTrue(m.contains("SyntaxError"))
        guard case .failure = CustomWidgetStore.render("var x = 1", widgetID: "t") else { return XCTFail("missing render() is an error") }
        guard case .success(let node) = CustomWidgetStore.render("function render(){ return {type:'hstack', children:[{type:'stat',label:'P',value:String(cc.data.pomodorosToday())},'plain']} }", widgetID: "t"),
              case .stack(true, let kids) = node else { return XCTFail() }
        XCTAssertEqual(kids.count, 2)
        // storage persists between renders
        let counter = CustomWidgetStore.samples.first { $0.0 == "Click Counter" }!.1
        let id = UUID().uuidString
        _ = CustomWidgetStore.render(counter, widgetID: id)
        guard case .success(.stack(false, let c2)) = CustomWidgetStore.render(counter, widgetID: id), case .stat(_, let v) = c2[0] else { return XCTFail() }
        XCTAssertEqual(v, "2")
        // .ccwidget round trip
        let def = CustomWidgetDef(name: "Share Me", author: "Tester", script: "function render(){return 'hi'}")
        CustomWidgetStore.save(def)
        let file = tempDir().appendingPathComponent("w.ccwidget")
        try CustomWidgetStore.export(def, to: file)
        let imported = try CustomWidgetStore.importBundle(file)
        XCTAssertEqual(imported.name, "Share Me"); XCTAssertEqual(imported.script, def.script); XCTAssertNotEqual(imported.id, def.id)
        try "{\"format\":\"other\",\"name\":\"x\",\"author\":\"\",\"script\":\"\"}".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try CustomWidgetStore.importBundle(file))
    }
}

import GRDB
