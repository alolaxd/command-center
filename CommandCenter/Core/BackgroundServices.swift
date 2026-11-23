import Foundation

/// Services that run regardless of which widgets are on screen.
@MainActor
enum BackgroundServices {
    private static var started = false

    static func start() {
        guard !started else { return }
        started = true
        HabitBusBridge.start()          // routes bus signals into habit auto-completion
        AgentActivity.start()           // scans agent logs/processes; feeds the menu bar ring
        APIHealthMonitor.start()        // pings monitored endpoints, alerts on failures
        BatteryStore.startHistory()     // charge history samples every 5 min
        ScreenTimeTracker.start()       // frontmost-app usage + pickups
        for extra in extraStarters { extra() }
    }

    /// Additional app-lifetime services registered by later modules.
    static var extraStarters: [@MainActor () -> Void] = []
}
