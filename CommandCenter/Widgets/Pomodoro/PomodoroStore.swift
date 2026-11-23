import Foundation
import GRDB

struct PomodoroSession: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pomodoro_session"
    var id: String = UUID().uuidString
    var start: Date
    var end: Date
    var minutes: Int
    var task: String?
}

@MainActor
enum PomodoroStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("pomodoro.v1") { db in
            try db.create(table: "pomodoro_session") { t in
                t.primaryKey("id", .text)
                t.column("start", .datetime).notNull()
                t.column("end", .datetime).notNull()
                t.column("minutes", .integer).notNull()
                t.column("task", .text)
            }
        }
    }

    static func log(_ s: PomodoroSession) { AppDatabase.shared.write { try s.insert($0) } }

    static func sessions(since: Date) -> [PomodoroSession] {
        AppDatabase.shared.read { try PomodoroSession.filter(Column("end") >= since).order(Column("end").desc).fetchAll($0) } ?? []
    }

    static func countToday() -> Int { sessions(since: Calendar.current.startOfDay(for: Date())).count }

    static func aiSummary() -> String {
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date().addingTimeInterval(-7 * 86400)
        let s = sessions(since: week.addingTimeInterval(-7 * 86400))
        let thisWeek = s.filter { $0.end >= week }
        let lastWeek = s.filter { $0.end < week }
        let tasks = Dictionary(grouping: thisWeek, by: { $0.task ?? "(no task)" }).map { "\($0.key): \($0.value.count)" }
        return """
        Pomodoros: today \(countToday()), this week \(thisWeek.count) (\(thisWeek.map(\.minutes).reduce(0, +)) focus minutes), last week \(lastWeek.count).
        By task this week: \(tasks.joined(separator: "; "))
        """
    }
}
