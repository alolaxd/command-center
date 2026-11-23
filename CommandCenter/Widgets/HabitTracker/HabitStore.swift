import Foundation
import GRDB

struct Habit: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "habit"
    var id: String = UUID().uuidString
    var name: String
    var symbol: String = "checkmark"
    var color: String = "green"
    var weeklyTarget: Int = 7          // 7 = daily habit
    var autoSource: String?            // "pomodoro", "health.workout", or a reminder title keyword
    var position: Int = 0
    var archived = false
}

struct HabitLog: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "habit_log"
    var habitId: String
    var day: String
    var count: Int = 1
}

@MainActor
enum HabitStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("habits.v1") { db in
            try db.create(table: "habit") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("color", .text).notNull()
                t.column("weeklyTarget", .integer).notNull()
                t.column("autoSource", .text)
                t.column("position", .integer).notNull()
                t.column("archived", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "habit_log") { t in
                t.column("habitId", .text).notNull().references("habit", onDelete: .cascade)
                t.column("day", .text).notNull()
                t.column("count", .integer).notNull()
                t.primaryKey(["habitId", "day"])
            }
        }
    }

    static func habits() -> [Habit] {
        var list = AppDatabase.shared.read { try Habit.filter(Column("archived") == false).order(Column("position")).fetchAll($0) } ?? []
        if list.isEmpty && !AppMeta.flag("habits.seeded") {
            AppMeta.setFlag("habits.seeded")
            let seeds = [Habit(name: "Focus", symbol: "timer", color: "red", autoSource: "pomodoro", position: 0),
                         Habit(name: "Exercise", symbol: "figure.run", color: "green", weeklyTarget: 4, autoSource: "health.workout", position: 1),
                         Habit(name: "Journal", symbol: "book", color: "purple", autoSource: "journal", position: 2)]
            AppDatabase.shared.write { db in for h in seeds { try h.insert(db) } }
            list = seeds
        }
        return list
    }

    static func save(_ h: Habit) { AppDatabase.shared.write { try h.save($0) } }
    static func delete(_ h: Habit) { AppDatabase.shared.write { _ = try h.delete($0) } }

    static func logs(since: Date) -> [String: Set<String>] {
        let key = since.dayKey
        let rows = AppDatabase.shared.read { try HabitLog.filter(Column("day") >= key).fetchAll($0) } ?? []
        return rows.reduce(into: [:]) { $0[$1.habitId, default: []].insert($1.day) }
    }

    static func allDays(_ habitId: String) -> [String] {
        AppDatabase.shared.read { try String.fetchAll($0, sql: "SELECT day FROM habit_log WHERE habitId = ? ORDER BY day", arguments: [habitId]) } ?? []
    }

    static func toggle(_ habitId: String, day: Date = Date()) {
        let key = day.dayKey
        AppDatabase.shared.write { db in
            if try HabitLog.filter(Column("habitId") == habitId && Column("day") == key).fetchCount(db) > 0 {
                try db.execute(sql: "DELETE FROM habit_log WHERE habitId = ? AND day = ?", arguments: [habitId, key])
            } else {
                try HabitLog(habitId: habitId, day: key).insert(db)
            }
        }
        WidgetBus.shared.publish(.dataChanged("habits"))
    }

    static func mark(_ habitId: String, day: Date = Date()) {
        AppDatabase.shared.write { db in
            try db.execute(sql: "INSERT INTO habit_log (habitId, day, count) VALUES (?, ?, 1) ON CONFLICT(habitId, day) DO UPDATE SET count = count + 1",
                           arguments: [habitId, day.dayKey])
        }
        WidgetBus.shared.publish(.dataChanged("habits"))
    }

    /// Auto-completion from other widgets: matches by habit name or autoSource.
    static func signal(_ source: String) {
        let s = source.lowercased()
        guard !s.isEmpty else { return }
        for h in habits() where h.name.lowercased() == s || h.autoSource?.lowercased() == s
            || (h.autoSource.map { !$0.isEmpty && s.contains($0.lowercased()) } ?? false) {
            mark(h.id)
        }
    }

    /// (current, best) streak in days.
    static func streaks(_ days: [String]) -> (Int, Int) {
        let set = Set(days)
        var current = 0
        var d = Date()
        if !set.contains(d.dayKey) { d = d.addingTimeInterval(-86400) }  // today not done yet doesn't break the streak
        while set.contains(d.dayKey) { current += 1; d = d.addingTimeInterval(-86400) }
        var best = 0, run = 0
        var prev: Date?
        for key in days.sorted() {
            guard let date = Date.fromDayKey(key) else { continue }
            if let p = prev, Calendar.current.dateComponents([.day], from: p, to: date).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = date
        }
        return (current, max(best, current))
    }

    static func aiSummary() -> String {
        let hs = habits()
        guard !hs.isEmpty else { return "" }
        let weekStart = Date().addingTimeInterval(-6 * 86400)
        let logs = logs(since: weekStart)
        return "Habits (last 7 days):\n" + hs.map { h in
            let (cur, best) = streaks(allDays(h.id))
            return "- \(h.name): \(logs[h.id]?.count ?? 0)/7 days, streak \(cur), best \(best)"
        }.joined(separator: "\n")
    }
}

import Combine

enum HabitBusBridge {
    @MainActor private static var cancellable: AnyCancellable?
    /// Routes bus signals (e.g. reminders completed, workouts) into habit auto-completion.
    @MainActor static func start() {
        cancellable = WidgetBus.shared.events.sink { event in
            if case .habitSignal(let name) = event { HabitStore.signal(name) }
        }
    }
}
