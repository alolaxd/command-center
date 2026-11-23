import Foundation
import GRDB

struct Countdown: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "countdown"
    var id: String = UUID().uuidString
    var name: String
    var start = Date()
    var target: Date
    var symbol = "flag.checkered"
    var color = "blue"

    var remaining: TimeInterval { target.timeIntervalSinceNow }
    var progress: Double { let total = target.timeIntervalSince(start); return total > 0 ? min(1, max(0, Date().timeIntervalSince(start) / total)) : 1 }
}

@MainActor
enum CountdownStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("countdown.v1") { db in
            try db.create(table: "countdown") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("start", .datetime).notNull()
                t.column("target", .datetime).notNull()
                t.column("symbol", .text).notNull()
                t.column("color", .text).notNull()
            }
        }
    }

    static func all() -> [Countdown] { AppDatabase.shared.read { try Countdown.order(Column("target")).fetchAll($0) } ?? [] }

    static func save(_ c: Countdown) {
        AppDatabase.shared.write { try c.save($0) }
        scheduleMilestones(c)
    }

    static func delete(_ c: Countdown) {
        AppDatabase.shared.write { _ = try c.delete($0) }
        Notifier.cancel(prefix: "countdown.\(c.id)")
    }

    static let milestones: [(TimeInterval, String)] = [(7 * 86400, "1 week to go"), (86400, "1 day to go"), (3600, "1 hour to go"), (0, "It's here!")]

    static func scheduleMilestones(_ c: Countdown) {
        Notifier.cancel(prefix: "countdown.\(c.id)")
        for (offset, text) in milestones {
            Notifier.schedule(c.name, text, at: c.target.addingTimeInterval(-offset), id: "countdown.\(c.id).\(Int(offset))")
        }
    }

    static func format(_ t: TimeInterval) -> String {
        if t <= 0 { return "Done" }
        let d = Int(t) / 86400, h = (Int(t) % 86400) / 3600, m = (Int(t) % 3600) / 60
        return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m \(Int(t) % 60)s"
    }

    /// "Product Launch in 12 days", "Vacation on 2027-01-15", "Demo friday 3pm".
    static func parse(_ text: String) -> Countdown? {
        let p = NaturalDateParser.parse(text)
        guard let date = p.date, date > Date() else { return nil }
        let name = p.title.replacingOccurrences(of: #"\s+(in|on|at)$"#, with: "", options: .regularExpression)
        return Countdown(name: name.isEmpty ? "Countdown" : name, target: date)
    }
}
