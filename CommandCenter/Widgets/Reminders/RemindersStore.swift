import EventKit
import Foundation
import GRDB

/// EventKit-backed reminders plus a local priority ordering (EventKit has no manual sort order).
@MainActor
enum RemindersStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("reminders.v1") { db in
            try db.create(table: "reminder_order") { t in
                t.primaryKey("id", .text)
                t.column("rank", .integer).notNull()
            }
        }
    }

    static var ek: EKEventStore { EventKitService.shared.store }

    static func fetchIncomplete(calendarIDs: [String]) async -> [EKReminder] {
        let cals = calendarIDs.isEmpty ? nil : ek.calendars(for: .reminder).filter { calendarIDs.contains($0.calendarIdentifier) }
        let predicate = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        return await withCheckedContinuation { cont in
            ek.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
    }

    static func lists() -> [EKCalendar] { ek.calendars(for: .reminder) }

    @discardableResult
    static func add(_ text: String, listID: String? = nil) -> EKReminder? {
        guard EventKitService.shared.remindersAuthorized else { return nil }
        let parsed = NaturalDateParser.parse(text)
        let r = EKReminder(eventStore: ek)
        r.title = parsed.title
        r.calendar = listID.flatMap { ek.calendar(withIdentifier: $0) } ?? ek.defaultCalendarForNewReminders()
        if let date = parsed.date {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
            if parsed.hasTime { comps.hour = Calendar.current.component(.hour, from: date); comps.minute = Calendar.current.component(.minute, from: date) }
            r.dueDateComponents = comps
            if parsed.hasTime { r.addAlarm(EKAlarm(absoluteDate: date)) }
        }
        do { try ek.save(r, commit: true); return r } catch { WidgetBus.shared.toast("Couldn't save reminder: \(error.localizedDescription)"); return nil }
    }

    static func complete(_ r: EKReminder, _ done: Bool = true) {
        r.isCompleted = done
        try? ek.save(r, commit: true)
        WidgetBus.shared.publish(.habitSignal(name: r.title ?? ""))
    }

    static func snooze(_ r: EKReminder, by interval: TimeInterval) {
        let base = max(Date(), r.dueDateComponents?.date ?? Date())
        let new = base.addingTimeInterval(interval)
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: new)
        r.alarms?.forEach { r.removeAlarm($0) }
        r.addAlarm(EKAlarm(absoluteDate: new))
        try? ek.save(r, commit: true)
    }

    static func delete(_ r: EKReminder) { try? ek.remove(r, commit: true) }

    // MARK: Local ordering
    static func ranks() -> [String: Int] {
        AppDatabase.shared.read { db in
            try Row.fetchAll(db, sql: "SELECT id, rank FROM reminder_order").reduce(into: [:]) { $0[$1["id"] as String] = $1["rank"] as Int }
        } ?? [:]
    }

    static func saveOrder(_ ids: [String]) {
        AppDatabase.shared.write { db in
            for (i, id) in ids.enumerated() {
                try db.execute(sql: "INSERT INTO reminder_order (id, rank) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET rank = excluded.rank", arguments: [id, i])
            }
        }
    }

    static func aiSummary() async -> String {
        guard EventKitService.shared.remindersAuthorized else { return "" }
        let items = await fetchIncomplete(calendarIDs: [])
        let lines = items.prefix(30).map { r -> String in
            let due = r.dueDateComponents?.date.map { " (due \($0.formatted(date: .abbreviated, time: .shortened)))" } ?? ""
            return "- \(r.title ?? "")\(due)"
        }
        return "Open reminders (\(items.count)):\n" + lines.joined(separator: "\n")
    }
}

extension EKReminder {
    var dueDate: Date? { dueDateComponents?.date }
}
