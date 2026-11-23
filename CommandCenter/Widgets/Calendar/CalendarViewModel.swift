import EventKit
import Foundation

@MainActor @Observable
final class CalendarViewModel {
    var anchor = Calendar.current.startOfDay(for: Date())
    var events: [EKEvent] = []
    var conflicts: Set<String> = []
    var now = Date()
    /// Live resize preview: event id → proposed end.
    var resizing: (id: String, end: Date)?

    func days(_ config: CalendarConfiguration) -> [Date] {
        (0..<config.days).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: anchor) }
    }

    func load(_ config: CalendarConfiguration) {
        now = Date()
        let end = Calendar.current.date(byAdding: .day, value: config.days, to: anchor)!
        events = CalendarStore.events(from: anchor, to: end, calendarIDs: config.calendarIDs)
        conflicts = CalendarStore.conflicts(events)
    }

    func shift(_ delta: Int, _ config: CalendarConfiguration) {
        anchor = Calendar.current.date(byAdding: .day, value: delta * config.days, to: anchor)!
        load(config)
    }

    func goToday(_ config: CalendarConfiguration) {
        anchor = Calendar.current.startOfDay(for: Date())
        load(config)
    }

    func events(on day: Date) -> [EKEvent] {
        events.filter { !$0.isAllDay && Calendar.current.isDate($0.startDate, inSameDayAs: day) }
    }

    func allDay(on day: Date) -> [EKEvent] {
        events.filter { $0.isAllDay && $0.startDate <= day.addingTimeInterval(86399) && $0.endDate > day }
    }

    func commitResize(_ e: EKEvent, config: CalendarConfiguration) {
        guard let r = resizing, r.id == e.eventIdentifier else { return }
        e.endDate = max(e.startDate.addingTimeInterval(900), r.end)
        CalendarStore.save(e)
        resizing = nil
        load(config)
    }
}
