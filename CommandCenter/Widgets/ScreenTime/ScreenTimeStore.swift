import AppKit
import Foundation
import GRDB

struct AppUsage: Codable, FetchableRecord, PersistableRecord, Identifiable, Hashable {
    static let databaseTableName = "app_usage"
    var id: String { day + bundleId }
    var day: String
    var bundleId: String
    var name: String
    var seconds: Double
}

/// Screen time is measured by Command Center itself: it tracks the frontmost app (NSWorkspace),
/// pauses while the screen is locked or the Mac sleeps, and counts unlocks as pickups.
/// (Apple's Screen Time database isn't available to third-party apps.)
@MainActor
enum ScreenTimeStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("screentime.v1") { db in
            try db.create(table: "app_usage") { t in
                t.column("day", .text).notNull()
                t.column("bundleId", .text).notNull()
                t.column("name", .text).notNull()
                t.column("seconds", .double).notNull()
                t.primaryKey(["day", "bundleId"])
            }
            try db.create(table: "pickups") { t in
                t.primaryKey("day", .text)
                t.column("count", .integer).notNull()
            }
        }
    }

    static func add(bundleId: String, name: String, seconds: Double, day: String = Date().dayKey) {
        guard seconds > 0.5 else { return }
        AppDatabase.shared.write { db in
            try db.execute(sql: """
                INSERT INTO app_usage (day, bundleId, name, seconds) VALUES (?, ?, ?, ?)
                ON CONFLICT(day, bundleId) DO UPDATE SET seconds = seconds + excluded.seconds, name = excluded.name
                """, arguments: [day, bundleId, name, seconds])
        }
    }

    static func pickup(day: String = Date().dayKey) {
        AppDatabase.shared.write {
            try $0.execute(sql: "INSERT INTO pickups (day, count) VALUES (?, 1) ON CONFLICT(day) DO UPDATE SET count = count + 1", arguments: [day])
        }
    }

    static func usage(day: String) -> [AppUsage] {
        AppDatabase.shared.read { try AppUsage.filter(Column("day") == day).order(Column("seconds").desc).fetchAll($0) } ?? []
    }

    static func pickups(day: String) -> Int {
        (AppDatabase.shared.read { try Int.fetchOne($0, sql: "SELECT count FROM pickups WHERE day = ?", arguments: [day]) } ?? nil) ?? 0
    }

    static func dailyTotals(days: Int) -> [(String, Double)] {
        (0..<days).reversed().map { i in
            let key = Date().addingTimeInterval(-Double(i) * 86400).dayKey
            return (key, usage(day: key).map(\.seconds).reduce(0, +))
        }
    }

    static func aiSummary() -> String {
        let u = usage(day: Date().dayKey)
        guard !u.isEmpty else { return "" }
        let total = u.map(\.seconds).reduce(0, +)
        return "Screen time today: \(total.compactDuration), \(pickups(day: Date().dayKey)) pickups. Top apps: " +
            u.prefix(5).map { "\($0.name) \($0.seconds.compactDuration)" }.joined(separator: ", ")
    }
}

@MainActor
enum ScreenTimeTracker {
    private static var current: (bundleId: String, name: String, since: Date)?
    private static var paused = false
    private static var observers: [Any] = []

    static func start() {
        guard observers.isEmpty else { return }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { switchTo(app) }
        })
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { pause() } })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { resume() } })
        }
        let dist = DistributedNotificationCenter.default()
        observers.append(dist.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in MainActor.assumeIsolated { pause() } })
        observers.append(dist.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { ScreenTimeStore.pickup(); resume() }
        })
        switchTo(NSWorkspace.shared.frontmostApplication)
        _ = TickScheduler.shared.subscribe(every: 60, fireNow: false) { flush() }
    }

    private static func switchTo(_ app: NSRunningApplication?) {
        flush()
        guard let app, !paused else { current = nil; return }
        current = (app.bundleIdentifier ?? app.localizedName ?? "unknown", app.localizedName ?? "Unknown", Date())
    }

    /// Credits time since the last flush to the current app (split across midnight).
    static func flush() {
        guard let c = current, !paused else { return }
        let now = Date()
        let midnight = Calendar.current.startOfDay(for: now)
        if c.since < midnight {
            ScreenTimeStore.add(bundleId: c.bundleId, name: c.name, seconds: midnight.timeIntervalSince(c.since), day: c.since.dayKey)
            ScreenTimeStore.add(bundleId: c.bundleId, name: c.name, seconds: now.timeIntervalSince(midnight))
        } else {
            ScreenTimeStore.add(bundleId: c.bundleId, name: c.name, seconds: now.timeIntervalSince(c.since))
        }
        current = (c.bundleId, c.name, now)
    }

    private static func pause() { flush(); paused = true; current = nil }
    private static func resume() { paused = false; switchTo(NSWorkspace.shared.frontmostApplication) }
}
