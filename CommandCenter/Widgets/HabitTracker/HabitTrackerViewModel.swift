import Foundation

@MainActor @Observable
final class HabitTrackerViewModel {
    var habits: [Habit] = []
    var logs: [String: Set<String>] = [:]
    var streaks: [String: (Int, Int)] = [:]

    func load(weeks: Int) {
        habits = HabitStore.habits()
        logs = HabitStore.logs(since: Date().addingTimeInterval(-Double(weeks * 7 + 7) * 86400))
        streaks = Dictionary(uniqueKeysWithValues: habits.map { ($0.id, HabitStore.streaks(HabitStore.allDays($0.id))) })
    }

    func done(_ h: Habit, _ day: Date) -> Bool { logs[h.id]?.contains(day.dayKey) ?? false }

    func add(_ name: String, weeks: Int) {
        HabitStore.save(Habit(name: name, position: habits.count))
        load(weeks: weeks)
    }

    /// Columns of 7 days (Mon…Sun), oldest first, ending with the current week.
    func gridWeeks(_ weeks: Int) -> [[Date]] {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let startOfWeek = cal.dateInterval(of: .weekOfYear, for: Date())!.start
        return (0..<weeks).reversed().map { w in
            let ws = cal.date(byAdding: .weekOfYear, value: -w, to: startOfWeek)!
            return (0..<7).map { cal.date(byAdding: .day, value: $0, to: ws)! }
        }
    }

    func weekCount(_ h: Habit) -> Int {
        let start = Calendar.current.dateInterval(of: .weekOfYear, for: Date())!.start
        return (0..<7).filter { done(h, Calendar.current.date(byAdding: .day, value: $0, to: start)!) }.count
    }
}
