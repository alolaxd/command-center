import Foundation

/// Every widget module available to the dashboard. Add a new widget by appending its descriptor.
@MainActor
enum WidgetRegistry {
    static let all: [WidgetDescriptor] = [
        PlaceholderWidget.descriptor,
        // Productivity & Organization
        RemindersWidget.descriptor, CalendarWidget.descriptor, InboxWidget.descriptor, NotesWidget.descriptor,
        KanbanWidget.descriptor, PomodoroWidget.descriptor, HabitTrackerWidget.descriptor, JournalWidget.descriptor,
        // AI & Development
        AgentMonitorWidget.descriptor, AIChatWidget.descriptor, GitDashboardWidget.descriptor, TerminalPanesWidget.descriptor,
        SnippetLibraryWidget.descriptor, APIHealthWidget.descriptor,
        // System & Hardware
        SystemMonitorWidget.descriptor, NetworkMonitorWidget.descriptor, DiskStorageWidget.descriptor, BatteryWidget.descriptor,
        // Communication & Information
        EmailDigestWidget.descriptor, WeatherWidget.descriptor, NewsFeedWidget.descriptor, BookmarksWidget.descriptor,
        // Finance & Data
        TickerWidget.descriptor, BudgetWidget.descriptor,
        // Health & Lifestyle
        HealthWidget.descriptor, NowPlayingWidget.descriptor,
        // Meta & Utility
        WorldClocksWidget.descriptor, CountdownWidget.descriptor, ScreenTimeWidget.descriptor,
        ShortcutsLauncherWidget.descriptor, CustomWidgetHost.descriptor,
    ]

    private static let byKind: [String: WidgetDescriptor] = Dictionary(uniqueKeysWithValues: all.map { ($0.kind, $0) })

    static func descriptor(_ kind: String) -> WidgetDescriptor? { byKind[kind] }

    static func grouped() -> [(WidgetCategory, [WidgetDescriptor])] {
        WidgetCategory.allCases.compactMap { cat in
            let items = all.filter { $0.category == cat && $0.kind != PlaceholderWidget.kind }
            return items.isEmpty ? nil : (cat, items)
        }
    }
}

enum WorkspacePresets {
    @MainActor
    static func make(_ name: String, _ symbol: String, _ kinds: [String]) -> Workspace {
        var ws = Workspace(name: name, symbol: symbol)
        for kind in kinds {
            guard let d = WidgetRegistry.descriptor(kind) else { continue }
            let items = ws.widgets.map { LayoutItem(id: $0.id, rect: $0.frame, minSize: GridSize(1, 1)) }
            let rect = GridLayoutEngine.firstFreeSlot(for: d.defaultSize, in: items, columns: ws.columns)
            ws.widgets.append(WidgetInstance(kind: kind, frame: rect, config: d.defaultConfig))
        }
        return ws
    }

    @MainActor
    static func defaults() -> [Workspace] {
        [
            make("Home", "house", ["reminders", "calendar", "weather", "inbox", "pomodoro", "habits", "worldclocks", "countdowns"]),
            make("Dev", "chevron.left.forwardslash.chevron.right", ["agents", "git", "terminal", "sysmon", "snippets", "apihealth"]),
            make("Finance", "chart.line.uptrend.xyaxis", ["tickers", "budget", "news"]),
            make("Health", "heart", ["health", "habits", "journal", "screentime", "music"]),
        ]
    }

    @MainActor
    static var presets: [(String, Workspace)] {
        [
            ("Focus", make("Focus", "scope", ["pomodoro", "kanban", "notes"])),
            ("Ops", make("Ops", "server.rack", ["apihealth", "sysmon", "network", "battery", "disk"])),
            ("Morning", make("Morning", "sunrise", ["weather", "email", "news", "calendar", "reminders"])),
            ("AI Lab", make("AI Lab", "sparkles", ["aichat", "agents", "terminal", "snippets"])),
        ]
    }
}
