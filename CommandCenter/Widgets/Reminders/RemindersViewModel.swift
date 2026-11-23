import EventKit
import Foundation

@MainActor @Observable
final class RemindersViewModel {
    var overdue: [EKReminder] = []
    var today: [EKReminder] = []
    var upcoming: [EKReminder] = []
    var undated: [EKReminder] = []
    var loading = false

    func load(_ config: RemindersConfiguration) async {
        guard EventKitService.shared.remindersAuthorized else { return }
        loading = true
        let all = await RemindersStore.fetchIncomplete(calendarIDs: config.listIDs)
        let ranks = RemindersStore.ranks()
        let sorted = all.sorted { a, b in
            let ra = ranks[a.calendarItemIdentifier] ?? Int.max, rb = ranks[b.calendarItemIdentifier] ?? Int.max
            if ra != rb { return ra < rb }
            return (a.dueDate ?? .distantFuture) < (b.dueDate ?? .distantFuture)
        }
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday)!
        let horizon = now.addingTimeInterval(TimeInterval(config.upcomingHours) * 3600)
        overdue = sorted.filter { ($0.dueDate ?? .distantFuture) < startOfToday || (($0.dueDate ?? .distantFuture) < now && $0.dueDateComponents?.hour != nil) }
        let overdueIDs = Set(overdue.map(\.calendarItemIdentifier))
        today = sorted.filter { !overdueIDs.contains($0.calendarItemIdentifier) && ($0.dueDate.map { $0 >= startOfToday && $0 < endOfToday } ?? false) }
        upcoming = sorted.filter { ($0.dueDate.map { $0 >= endOfToday && $0 < horizon } ?? false) }
        undated = config.showUndated ? sorted.filter { $0.dueDate == nil } : []
        loading = false
    }

    func move(in section: [EKReminder], from: IndexSet, to: Int, config: RemindersConfiguration) {
        var items = section
        items.move(fromOffsets: from, toOffset: to)
        let others = (overdue + today + upcoming + undated).filter { r in !items.contains { $0 === r } }
        RemindersStore.saveOrder((items + others).map(\.calendarItemIdentifier))
        Task { await load(config) }
    }
}
