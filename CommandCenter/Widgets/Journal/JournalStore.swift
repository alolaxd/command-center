import Foundation
import GRDB

struct JournalEntry: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "journal_entry"
    var id: String { day }
    var day: String
    var body: String = ""
    var mood: Int = 0          // 0 = unset, 1…5
    var wentWell: String = ""
    var improve: String = ""
    var grateful: String = ""
    var updatedAt = Date()

    var isEmpty: Bool { body.isEmpty && wentWell.isEmpty && improve.isEmpty && grateful.isEmpty && mood == 0 }
    static let moods = ["", "😞", "🙁", "😐", "🙂", "😄"]
}

struct JournalSummary: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "journal_summary"
    var weekStart: String
    var text: String
    var createdAt = Date()
}

@MainActor
enum JournalStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("journal.v1") { db in
            try db.create(table: "journal_entry") { t in
                t.primaryKey("day", .text)
                t.column("body", .text).notNull()
                t.column("mood", .integer).notNull()
                t.column("wentWell", .text).notNull()
                t.column("improve", .text).notNull()
                t.column("grateful", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
            try db.create(table: "journal_summary") { t in
                t.primaryKey("weekStart", .text)
                t.column("text", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
    }

    static func entry(_ day: Date) -> JournalEntry {
        (AppDatabase.shared.read { try JournalEntry.fetchOne($0, key: day.dayKey) } ?? nil) ?? JournalEntry(day: day.dayKey)
    }

    static func save(_ e: JournalEntry) {
        var x = e
        x.updatedAt = Date()
        if x.isEmpty { AppDatabase.shared.write { _ = try JournalEntry.deleteOne($0, key: x.day) }; return }
        AppDatabase.shared.write { try x.save($0) }
        if x.day == Date().dayKey { HabitStore.signal("journal") }
    }

    static func entries(from: Date, to: Date) -> [JournalEntry] {
        AppDatabase.shared.read {
            try JournalEntry.filter(Column("day") >= from.dayKey && Column("day") <= to.dayKey).order(Column("day")).fetchAll($0)
        } ?? []
    }

    static func daysWithEntries() -> Set<String> {
        Set(AppDatabase.shared.read { try String.fetchAll($0, sql: "SELECT day FROM journal_entry") } ?? [])
    }

    static func summary(weekStart: Date) -> JournalSummary? {
        AppDatabase.shared.read { try JournalSummary.fetchOne($0, key: weekStart.dayKey) } ?? nil
    }

    static func saveSummary(_ s: JournalSummary) { AppDatabase.shared.write { try s.save($0) } }

    static func weekStart(_ d: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: d)!.start
    }

    /// Generates an AI summary of a week's entries.
    static func generateSummary(weekStart: Date) async throws -> String {
        let entries = entries(from: weekStart, to: weekStart.addingTimeInterval(6 * 86400))
        guard !entries.isEmpty else { return "No entries this week." }
        let text = entries.map { e in
            "## \(e.day) mood \(e.mood)/5\n\(e.body)\nWent well: \(e.wentWell)\nCould improve: \(e.improve)\nGrateful for: \(e.grateful)"
        }.joined(separator: "\n\n")
        let summary = try await AIService.shared.complete(
            system: "You write warm, concise weekly reviews of a private journal. Use Markdown: a 2-3 sentence overview, 'Highlights', 'Patterns' (mood trend, recurring themes), and one gentle suggestion for next week.",
            [AIMessage(role: .user, content: text)])
        saveSummary(JournalSummary(weekStart: weekStart.dayKey, text: summary))
        return summary
    }

    static func aiSummary() -> String {
        let es = entries(from: Date().addingTimeInterval(-6 * 86400), to: Date())
        guard !es.isEmpty else { return "" }
        let moods = es.filter { $0.mood > 0 }.map(\.mood)
        let avg = moods.isEmpty ? "n/a" : String(format: "%.1f", Double(moods.reduce(0, +)) / Double(moods.count))
        return "Journal: \(es.count) entries in the last 7 days, average mood \(avg)/5."
    }
}
