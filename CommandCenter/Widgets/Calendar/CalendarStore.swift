import EventKit
import Foundation

/// EventKit calendar queries and mutations.
@MainActor
enum CalendarStore {
    static var ek: EKEventStore { EventKitService.shared.store }

    static func calendars() -> [EKCalendar] { ek.calendars(for: .event) }

    static func events(from start: Date, to end: Date, calendarIDs: [String]) -> [EKEvent] {
        guard EventKitService.shared.eventsAuthorized else { return [] }
        let cals = calendarIDs.isEmpty ? nil : calendars().filter { calendarIDs.contains($0.calendarIdentifier) }
        return ek.events(matching: ek.predicateForEvents(withStart: start, end: end, calendars: cals))
            .sorted { $0.startDate < $1.startDate }
    }

    @discardableResult
    static func create(title: String, start: Date, end: Date, calendarID: String? = nil) -> EKEvent? {
        let e = EKEvent(eventStore: ek)
        e.title = title
        e.startDate = start
        e.endDate = end
        e.calendar = calendarID.flatMap { ek.calendar(withIdentifier: $0) } ?? ek.defaultCalendarForNewEvents
        do { try ek.save(e, span: .thisEvent, commit: true); return e }
        catch { WidgetBus.shared.toast("Couldn't create event: \(error.localizedDescription)"); return nil }
    }

    /// Creates an event from natural language ("Lunch with Sam friday 1pm").
    @discardableResult
    static func create(fromText text: String) -> EKEvent? {
        let p = NaturalDateParser.parse(text)
        let start = p.date ?? Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date().addingTimeInterval(86400))!
        return create(title: p.title, start: start, end: start.addingTimeInterval(p.duration ?? 3600))
    }

    static func save(_ e: EKEvent) {
        do { try ek.save(e, span: .thisEvent, commit: true) }
        catch { WidgetBus.shared.toast("Couldn't update event: \(error.localizedDescription)") }
    }

    static func delete(_ e: EKEvent) { try? ek.remove(e, span: .thisEvent, commit: true) }

    /// IDs of timed events that overlap another timed event.
    static func conflicts(_ events: [EKEvent]) -> Set<String> {
        let timed = events.filter { !$0.isAllDay && $0.availability != .free }
        var ids = Set<String>()
        for (i, a) in timed.enumerated() {
            for b in timed[(i + 1)...] where a.startDate < b.endDate && b.startDate < a.endDate {
                ids.insert(a.eventIdentifier ?? ""); ids.insert(b.eventIdentifier ?? "")
            }
        }
        return ids
    }

    static func aiSummary() async -> String {
        guard EventKitService.shared.eventsAuthorized else { return "" }
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86400)
        let evs = events(from: start, to: start.addingTimeInterval(8 * 86400), calendarIDs: [])
        let lines = evs.prefix(40).map { "- \($0.startDate.formatted(date: .abbreviated, time: .shortened)): \($0.title ?? "")" }
        return "Calendar (yesterday → next 7 days):\n" + lines.joined(separator: "\n")
    }
}
