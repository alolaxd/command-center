import AppKit
import GRDB
import SwiftUI
import XCTest
@testable import Command_Center

/// Generates README / release screenshots from sample data only (demo mode, isolated test database).
/// Runs only when /tmp/cc-screenshots/.enable exists:
///   mkdir -p /tmp/cc-screenshots && touch /tmp/cc-screenshots/.enable && ./build.sh test -only-testing:CommandCenterTests/ScreenshotGenerator
@MainActor
final class ScreenshotGenerator: XCTestCase {
    let outDir = URL(fileURLWithPath: "/tmp/cc-screenshots")

    override func setUp() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: outDir.appendingPathComponent(".enable").path), "screenshot generation not requested")
        AppPaths.demoMode = true
        UserDefaults.standard.set(84.0, forKey: SettingsKey.rowHeight)
        seed()
    }

    // MARK: Sample data
    private func wipe(_ tables: [String]) {
        AppDatabase.shared.write { db in for t in tables { try db.execute(sql: "DELETE FROM \(t)") } }
    }

    private func seed() {
        wipe(["kanban_card", "inbox_item", "pomodoro_session", "habit_log", "habit", "journal_entry", "journal_summary", "agent_session", "agent_usage",
              "snippet", "api_check", "bookmark", "budget_txn", "budget_recurring", "health_value", "countdown", "app_usage", "pickups",
              "ai_message", "custom_widget", "news_item", "music_history"])
        for n in NotesStore.all() { try? FileManager.default.removeItem(at: n.url) }
        NotesStore.reindexAll()
        let now = Date()
        func day(_ d: Int) -> Date { now.addingTimeInterval(Double(-d) * 86400) }

        // Kanban
        for (t, c, l) in [("Design onboarding flow", KanbanColumn.backlog, "app"), ("Dark mode polish", .backlog, "app"), ("Rate limiting for /v2", .todo, "api"),
                          ("Write launch blog post", .todo, "marketing"), ("Stripe webhooks", .inProgress, "api"), ("Widget gallery", .inProgress, "app"),
                          ("Pricing page copy", .review, "marketing"), ("Migrate to Postgres 17", .done, "api"), ("App icon", .done, "app")] {
            KanbanStore.addCard(title: t, column: c, lane: l, link: t == "Stripe webhooks" ? .repo("~/Projects/acme-api") : nil)
        }
        // Notes
        _ = NotesStore.create(title: "Reading List", body: "- The Pragmatic Programmer\n- Designing Data-Intensive Applications\n#books")
        _ = NotesStore.create(title: "Announcement Thread", body: "Draft the announcement. See [[Launch Plan]]. #launch")
        Thread.sleep(forTimeInterval: 1.1)   // make Launch Plan the most recently edited note
        _ = NotesStore.create(title: "Launch Plan", body: """
        # Launch Plan
        Ship **v1.0** on the 8th. Owner: product team. #launch #planning

        ## Checklist
        - [x] Final QA pass
        - [x] Press kit
        - [ ] Record demo video
        - [ ] Schedule [[Announcement Thread]]

        > Keep the scope small — polish over features.

        ```sh
        ./build.sh && ./release.sh v1.0.0
        ```
        """)
        // Inbox
        InboxStore.add("Idea: weekly review template for the journal")
        InboxStore.add("https://developer.apple.com/documentation/swiftui")
        InboxStore.add("Call the venue about the projector")
        var stale = InboxItem(kind: .text, text: "Renew domain before it expires"); stale.createdAt = day(9)
        AppDatabase.shared.write { try stale.insert($0) }
        // Habits
        let habits = [Habit(name: "Focus", symbol: "timer", color: "red", autoSource: "pomodoro", position: 0),
                      Habit(name: "Exercise", symbol: "figure.run", color: "green", weeklyTarget: 4, autoSource: "health.workout", position: 1),
                      Habit(name: "Read", symbol: "book", color: "purple", position: 2),
                      Habit(name: "Meditate", symbol: "leaf", color: "teal", position: 3)]
        AppMeta.setFlag("habits.seeded")
        var rng = SystemRandomNumberGenerator()
        for (i, h) in habits.enumerated() {
            HabitStore.save(h)
            for d in 0..<120 where (d < 6 && i < 2) || Double.random(in: 0...1, using: &rng) < [0.8, 0.55, 0.65, 0.45][i] { HabitStore.toggle(h.id, day: day(d)) }
        }
        // Pomodoro history
        for d in 0..<7 { for k in 0..<(d == 0 ? 5 : Int.random(in: 3...8)) {
            let end = day(d).addingTimeInterval(Double(-k) * 1800)
            PomodoroStore.log(PomodoroSession(start: end.addingTimeInterval(-1500), end: end, minutes: 25, task: ["Stripe webhooks", "Widget gallery", "Launch post"][k % 3]))
        } }
        // Journal
        var j = JournalEntry(day: now.dayKey)
        j.body = "Shipped the webhook retry logic and paired on the widget gallery. Long walk at lunch."
        j.mood = 4; j.wentWell = "Deep focus block in the morning"; j.improve = "Fewer context switches after 3pm"; j.grateful = "A calm, sunny day"
        JournalStore.save(j)
        for d in 1..<6 { var e = JournalEntry(day: day(d).dayKey); e.body = "Day \(d)"; e.mood = [3, 4, 5, 4, 3][d - 1]; JournalStore.save(e) }
        // Countdowns
        for (n, days, sym, color) in [("Product Launch", 12.4, "paperplane.fill", "blue"), ("Team Offsite", 30.2, "airplane", "orange"), ("Conference Talk", 64.0, "mic.fill", "purple")] {
            CountdownStore.save(Countdown(name: n, start: now.addingTimeInterval(-days * 86400 * 0.8), target: now.addingTimeInterval(days * 86400), symbol: sym, color: color))
        }
        // Agent sessions (sample data, not read from disk)
        let sessions: [(AgentProvider, String, String, String, Double, Int, Double, String)] = [
            (.claudeCode, "Refactor auth middleware to async/await", "~/Projects/acme-api", "claude-opus-5-5", 0.2, 1_840_000, 6.42, "Tool: Edit"),
            (.claudeCode, "Add widget gallery search", "~/Projects/dashboard", "claude-sonnet-5-5", 0.5, 620_000, 1.12, "Running tests…"),
            (.codex, "Fix flaky webhook retry test", "~/Projects/acme-api", "gpt-5-codex", 25, 410_000, 0.98, ""),
            (.aider, "Update README install steps", "~/Projects/cli", "claude-sonnet-5-5", 180, 96_000, 0.21, ""),
            (.openCode, "Explore Postgres 17 migration", "~/Projects/acme-api", "claude-opus-5-5", 1440, 1_220_000, 3.80, ""),
        ]
        AppDatabase.shared.write { db in
            for (i, s) in sessions.enumerated() {
                let last = now.addingTimeInterval(-s.4 * 60)
                let row = AgentSession(id: "demo-\(i)", provider: s.0, title: s.1, cwd: s.2, model: s.3, startedAt: last.addingTimeInterval(-3600 * Double(i + 1)),
                                       lastActivity: last, inputTokens: s.5 / 3, outputTokens: s.5 / 10, cacheTokens: s.5 - s.5 / 3 - s.5 / 10, cost: s.6, lastEvent: s.7)
                try row.save(db)
            }
            for d in 0..<40 {
                for (p, base) in [(AgentProvider.claudeCode, 6.0), (.codex, 1.4), (.openCode, 0.9), (.aider, 0.3)] where Double.random(in: 0...1) < 0.8 {
                    try AgentUsage(sessionId: "hist-\(p.rawValue)-\(d)", provider: p, day: day(d).dayKey, cost: base * Double.random(in: 0.3...1.6), tokens: Int(base * 200_000)).insert(db)
                }
            }
        }
        // Snippets
        for (t, code) in [("Deploy to staging", "git push origin main && fly deploy --app acme-staging"),
                          ("Debounce", "func debounce(_ delay: Duration, _ action: @escaping () async -> Void) -> () -> Void {\n    var task: Task<Void, Never>?\n    return {\n        task?.cancel()\n        task = Task { try? await Task.sleep(for: delay); await action() }\n    }\n}"),
                          ("Find large files", "find . -type f -size +100M -exec ls -lh {} \\; | sort -k5 -h"),
                          ("Active users (SQL)", "SELECT date_trunc('day', created_at) AS day, count(DISTINCT user_id)\nFROM events\nWHERE created_at > now() - interval '30 days'\nGROUP BY 1 ORDER BY 1;")] {
            var s = SnippetStore.importText(code, title: t); s.tags = t.contains("SQL") ? "analytics" : "ops"; SnippetStore.save(s)
        }
        // Budget
        for (amt, cat, note, d) in [(84.20, "Groceries", "Weekly shop", 1), (12.50, "Dining", "Lunch", 0), (42.0, "Transport", "Train pass", 3), (18.99, "Subscriptions", "Music", 5),
                                    (1500.0, "Housing", "Rent", 7), (64.0, "Fun", "Concert", 4), (36.8, "Dining", "Dinner", 2), (120.4, "Groceries", "Market", 8), (9.99, "Subscriptions", "Cloud", 9)] {
            BudgetStore.save(BudgetTransaction(amount: amt, category: cat, date: day(min(d, Calendar.current.component(.day, from: now) - 1)), note: note))
        }
        // Health
        for d in 0..<7 {
            let k = day(d).dayKey
            for (m, v) in [(HealthMetric.steps, Double.random(in: 6000...11000)), (.activeCalories, Double.random(in: 320...560)), (.exerciseMinutes, Double.random(in: 18...45)),
                           (.standHours, Double.random(in: 8...12)), (.heartRate, Double.random(in: 58...68)), (.sleepHours, Double.random(in: 6.4...8.1)), (.water, Double.random(in: 1200...2200))] {
                HealthStore.set(m, v.rounded(), day: k, source: "import")
            }
        }
        // Screen time (sample)
        for (id, name, secs) in [("com.apple.dt.Xcode", "Xcode", 11800.0), ("com.apple.Safari", "Safari", 6400.0), ("com.apple.Terminal", "Terminal", 3900.0),
                                 ("com.apple.Notes", "Notes", 1900.0), ("com.apple.Music", "Music", 1500.0), ("com.apple.Preview", "Preview", 600.0)] {
            ScreenTimeStore.add(bundleId: id, name: name, seconds: secs)
            for d in 1..<7 { ScreenTimeStore.add(bundleId: id, name: name, seconds: secs * Double.random(in: 0.5...1.3), day: day(d).dayKey) }
        }
        for _ in 0..<37 { ScreenTimeStore.pickup() }
        // Bookmarks
        for (t, u, f) in [("GitHub", "https://github.com", "Dev"), ("Apple Developer", "https://developer.apple.com", "Dev"), ("Hacker News", "https://news.ycombinator.com", "Read"),
                          ("Wikipedia", "https://www.wikipedia.org", "Read"), ("Figma", "https://www.figma.com", "Design"), ("Swift Forums", "https://forums.swift.org", "Dev")] {
            BookmarksStore.add(url: u, title: t, folder: f)
        }
        // News (sample articles, no live fetch)
        let headlines = [("Swift 6.4 brings faster incremental builds", "Swift Blog"), ("A practical guide to local-first apps", "Engineering Weekly"),
                         ("Designing calm interfaces for power users", "UX Journal"), ("SQLite turns 26: lessons from the most deployed database", "Engineering Weekly"),
                         ("How we cut our CI time in half", "DevOps Digest"), ("The case for keyboard-first productivity tools", "UX Journal"),
                         ("Understanding memory pressure on Apple silicon", "Swift Blog"), ("Shipping a menu bar app: what we learned", "Indie Dev")]
        NewsStore.upsert(headlines.enumerated().map { i, h in
            NewsItem(id: "demo-\(i)", feed: "demo://sample", feedTitle: h.1, title: h.0, link: "https://example.com/\(i)",
                     published: now.addingTimeInterval(Double(-i) * 4200 - 600), summary: "", read: i > 4)
        })
        // AI chat (sample conversation)
        let convo = demoChatID.uuidString
        AIChatStore.append(ChatMessage(conversation: convo, role: "user", content: "How many pomodoros did I do this week, and on what?"))
        AIChatStore.append(ChatMessage(conversation: convo, role: "assistant", content: "You completed **31 pomodoros** this week (12.9 focus hours):\n\n- **Stripe webhooks** — 12\n- **Widget gallery** — 11\n- **Launch post** — 8\n\nThat's up from 24 last week. Your Focus habit streak is at **6 days**."))
        // Custom widget
        let cw = CustomWidgetDef(name: "Habit Streaks", author: "Command Center", script: CustomWidgetStore.samples.first { $0.0 == "Habit Streaks" }!.1)
        CustomWidgetStore.save(cw)
        customWidgetID = cw.id
    }

    let demoChatID = UUID(uuidString: "00000000-0000-0000-0000-00000000C0DE")!
    var customWidgetID = ""

    // MARK: Layouts
    private func ws(_ name: String, _ symbol: String, _ items: [(String, Int, Int, Int, Int, Data?)]) -> Workspace {
        var w = Workspace(name: name, symbol: symbol)
        for (kind, x, y, wd, h, cfg) in items {
            w.widgets.append(WidgetInstance(kind: kind, frame: GridRect(x: x, y: y, w: wd, h: h), config: cfg ?? WidgetRegistry.descriptor(kind)!.defaultConfig))
        }
        return w
    }

    private func cfg<C: Encodable>(_ c: C) -> Data { try! JSONEncoder().encode(c) }

    private var workspaces: [Workspace] {
        var api = APIHealthConfiguration()
        api.endpoints = [APIEndpoint(name: "GitHub API", url: "https://api.github.com"), APIEndpoint(name: "Marketing site", url: "https://example.com"),
                         APIEndpoint(name: "Open-Meteo", url: "https://api.open-meteo.com/v1/forecast?latitude=0&longitude=0&current=temperature_2m")]
        var custom = CustomWidgetConfiguration(); custom.definitionID = customWidgetID
        var tickers = TickerConfiguration()
        tickers.entries = [TickerEntry(symbol: "AAPL", holdings: 20), TickerEntry(symbol: "MSFT", holdings: 8), TickerEntry(symbol: "^GSPC"), TickerEntry(symbol: "crypto:bitcoin", holdings: 0.15)]
        var weather = WeatherConfiguration(); weather.place = .init(name: "Lisbon, PT", lat: 38.7167, lon: -9.1333)
        var clocks = WorldClocksConfiguration()
        clocks.zones = [.init(identifier: "America/Los_Angeles", label: "San Francisco"), .init(identifier: "America/New_York", label: ""),
                        .init(identifier: "Europe/London", label: ""), .init(identifier: "Europe/Berlin", label: "")]
        var news = NewsFeedConfiguration(); news.feeds = ["demo://sample"]
        return [
            ws("Home", "house", [("weather", 0, 0, 3, 4, cfg(weather)), ("pomodoro", 3, 0, 2, 4, nil), ("kanban", 5, 0, 7, 4, nil),
                                 ("habits", 0, 4, 4, 3, nil), ("countdowns", 4, 4, 3, 3, nil), ("worldclocks", 7, 4, 5, 3, cfg(clocks))]),
            ws("Dev", "chevron.left.forwardslash.chevron.right", [("agents", 0, 0, 7, 4, nil), ("sysmon", 7, 0, 5, 4, nil),
                                 ("terminal", 0, 4, 7, 4, nil), ("snippets", 7, 4, 5, 4, nil), ("apihealth", 0, 8, 5, 3, cfg(api)), ("inbox", 5, 8, 7, 3, nil)]),
            ws("Finance", "chart.line.uptrend.xyaxis", [("tickers", 0, 0, 5, 4, cfg(tickers)), ("budget", 5, 0, 4, 4, nil), ("news", 9, 0, 3, 7, cfg(news)),
                                 ("shortcuts", 0, 4, 4, 3, nil), ("bookmarks", 4, 4, 5, 3, nil)]),
            ws("Health", "heart", [("health", 0, 0, 4, 4, nil), ("journal", 4, 0, 4, 4, nil), ("screentime", 8, 0, 4, 4, nil),
                                   ("notes", 0, 4, 7, 4, nil), ("customwidget", 7, 4, 5, 2, cfg(custom)), ("battery", 7, 6, 5, 2, nil)]),
        ]
    }

    // MARK: Capture
    /// Composited pixels of one of our own windows via the window server (includes layer
    /// backgrounds, terminal text and materials). Falls back to cacheDisplay when unavailable.
    private func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        let f = unsafeBitCast(sym, to: Fn.self)
        // includingWindow = 1<<3; boundsIgnoreFraming = 1<<0, bestResolution = 1<<3
        return f(.null, 1 << 3, UInt32(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
    }

    private func capture(window: NSWindow, _ name: String) throws {
        window.displayIfNeeded()
        pump(0.3)
        if let img = windowImage(window), img.width > 10 {
            let rep = NSBitmapImageRep(cgImage: img)
            try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name + ".png"))
            print("CCSHOT \(name) via window server \(img.width)x\(img.height)")
        } else {
            try capture(window.contentView!.superview ?? window.contentView!, name)
            print("CCSHOT \(name) via cacheDisplay")
        }
    }

    private func capture(_ view: NSView, _ name: String) throws {
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw CocoaError(.featureUnsupported) }
        view.cacheDisplay(in: view.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name + ".png"))
    }

    private func window(_ size: NSSize, dark: Bool = true, chrome: Bool = true) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: size),
                         styleMask: chrome ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView] : [.borderless],
                         backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        w.title = "Command Center"
        return w
    }

    private func pump(_ s: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    func testGenerateScreenshots() throws {
        let store = WorkspaceStore.shared
        let saved = store.workspaces
        let savedCurrency = UserDefaults.standard.string(forKey: SettingsKey.currency)
        UserDefaults.standard.set("USD", forKey: SettingsKey.currency)
        defer {
            store.workspaces = saved; store.saveNow(); AppPaths.demoMode = false; PomodoroEngine.shared.reset()
            UserDefaults.standard.set(savedCurrency, forKey: SettingsKey.currency)   // tests share the app's defaults domain
        }
        store.workspaces = workspaces
        AgentActivity.markDemoScan()
        for w in NSApp.windows where w.isVisible { w.orderOut(nil) }   // the test host's own dashboard window

        // A running pomodoro shows the live timer (and the notch live activity).
        var pc = PomodoroConfiguration(); pc.autoStartBreaks = false
        PomodoroEngine.shared.apply(pc)
        PomodoroEngine.shared.start(task: "Stripe webhooks")

        for (i, (name, dark)) in [("dashboard-home", true), ("dashboard-dev", true), ("dashboard-finance", true), ("dashboard-health", false)].enumerated() {
            store.select(store.workspaces[i].id)
            let w = window(NSSize(width: 1500, height: i == 1 ? 1130 : 900), dark: dark)
            w.contentView = NSHostingView(rootView: MainView().modifier(AppearanceModifier(theme: dark ? "Dark" : "Light", accent: "system", textScale: TextScale.standard.rawValue)))
            w.makeKeyAndOrderFront(nil)
            if i == 1 {   // put something tasteful in the terminal
                pump(2)
                for s in TerminalManager.shared.sessions.values {
                    s.runLine("clear; printf '\\033[1;32m✓\\033[0m 214 tests passed  \\033[2m(12.4s)\\033[0m\\n'; git log --oneline 2>/dev/null | head -3; printf '\\033[36mfeat:\\033[0m retry webhooks with backoff\\n\\033[36mfix:\\033[0m  debounce widget search\\n\\033[35mchore:\\033[0m bump Swift tools to 6.4\\n'")
                }
            }
            pump(i == 0 || i == 2 ? 9 : 6)   // network-backed widgets (weather, markets, news, favicons)
            try capture(window: w, name)
            w.orderOut(nil)
        }

        // Widget gallery
        let g = window(NSSize(width: 760, height: 560), chrome: false)
        g.contentView = NSHostingView(rootView: WidgetGalleryView().background(Color(nsColor: .windowBackgroundColor)))
        g.orderFront(nil); pump(1)
        try capture(window: g, "widget-gallery"); g.orderOut(nil)

        // Settings
        let s = window(NSSize(width: 560, height: 560), chrome: false)
        s.contentView = NSHostingView(rootView: SettingsView().background(Color(nsColor: .windowBackgroundColor)))
        s.orderFront(nil); pump(1)
        try capture(window: s, "settings"); s.orderOut(nil)

        // Ask AI widget (sample conversation)
        let chatInst = WidgetInstance(id: demoChatID, kind: "aichat", frame: GridRect(x: 0, y: 0, w: 5, h: 5), config: WidgetRegistry.descriptor("aichat")!.defaultConfig)
        let c = window(NSSize(width: 520, height: 470), chrome: false)
        c.contentView = NSHostingView(rootView: WidgetCardView(instance: chatInst, isFocused: false, isDragging: false, onMove: { _ in }, onResize: { _ in })
            .padding(12).frame(width: 520, height: 470).background(Color(nsColor: .windowBackgroundColor)))
        c.orderFront(nil); pump(1.5)
        try capture(window: c, "ask-ai"); c.orderOut(nil)

        // Menu bar panel: terminal + palette, and clipboard ring (sample entries)
        let model = MenuBarModel()
        model.paletteOutput = "Reminder “Send invoices” due Tomorrow at 9:00 AM"
        model.input = ">start pomodoro Launch post"
        let q = TerminalManager.shared.quick
        q.runLine("clear; printf '\\033[1;34m==>\\033[0m Building \\033[1macme-api\\033[0m\\n\\033[32m✓\\033[0m Compiled 48 files in 3.2s\\n\\033[33m!\\033[0m 2 warnings\\n'")
        pump(1.5)
        let mb = NSHostingView(rootView: panelChrome(MenuBarView(model: model)))
        let mw = window(NSSize(width: 700, height: 510), chrome: false); mw.contentView = mb; mw.orderFront(nil); pump(1)
        try capture(window: mw, "menubar-terminal")
        ClipboardHistory.shared.clear()
        for t in ["https://github.com/acme/api/pull/482", "brew install xcodegen", "Meeting moved to 3:30pm", "SELECT count(*) FROM events;", "Thanks — talk soon!"] {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string); ClipboardHistory.shared.poll()
        }
        model.tab = .clipboard; pump(1)
        try capture(window: mw, "menubar-clipboard"); mw.orderOut(nil)
        ClipboardHistory.shared.clear()

        // Notch island: expanded and live-activity states over a stand-in menu bar.
        let state = NotchState()
        state.notchHeight = 32; state.notchWidth = 188; state.isHardwareNotch = true
        state.pomodoroRunning = true; state.pomodoroRemaining = 18 * 60 + 42; state.agentsRunning = 2
        for (mode, name, size) in [(NotchController.Mode.live, "notch-live", NSSize(width: 900, height: 120)), (.expanded, "notch-expanded", NSSize(width: 900, height: 560))] {
            state.mode = mode
            let islandSize = NotchController.frame(for: mode, notch: .init(rect: CGRect(x: 356, y: size.height - 32, width: 188, height: 32), isHardware: true),
                                                   screenFrame: CGRect(origin: .zero, size: size)).size
            model.tab = .terminal
            let v = NSHostingView(rootView: ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.16, green: 0.2, blue: 0.3), Color(red: 0.32, green: 0.24, blue: 0.36)], startPoint: .top, endPoint: .bottom)
                Rectangle().fill(.black.opacity(0.25)).frame(height: 32)
                NotchRootView(state: state, model: model).frame(width: islandSize.width, height: islandSize.height)
            }.frame(width: size.width, height: size.height))
            let nw = window(size, chrome: false); nw.contentView = v; nw.orderFront(nil); pump(1.2)
            try capture(window: nw, name); nw.orderOut(nil)
        }
    }

    private func panelChrome<V: View>(_ v: V) -> some View {
        v.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
            .padding(20)
            .background(Color(red: 0.2, green: 0.22, blue: 0.27))
            .environment(\.colorScheme, .dark)
    }
}
