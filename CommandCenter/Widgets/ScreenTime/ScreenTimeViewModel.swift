import Foundation

@MainActor @Observable
final class ScreenTimeViewModel {
    var usage: [AppUsage] = []
    var pickups = 0
    var week: [(String, Double)] = []

    var total: Double { usage.map(\.seconds).reduce(0, +) }

    func load() {
        ScreenTimeTracker.flush()
        let key = Date().dayKey
        usage = ScreenTimeStore.usage(day: key)
        pickups = ScreenTimeStore.pickups(day: key)
        week = ScreenTimeStore.dailyTotals(days: 7)
    }
}
