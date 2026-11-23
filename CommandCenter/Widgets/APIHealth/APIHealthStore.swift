import Foundation
import GRDB

struct APIEndpoint: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var method = "GET"
    var expectedStatus = 200
    var interval: Double = 60
    var timeout: Double = 10
}

struct APICheck: Codable, FetchableRecord, PersistableRecord, Hashable {
    static let databaseTableName = "api_check"
    var endpointId: String
    var timestamp: Date
    var status: Int
    var latencyMs: Double
    var ok: Bool
    var error: String?
}

@MainActor
enum APIHealthStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("apihealth.v1") { db in
            try db.create(table: "api_check") { t in
                t.column("endpointId", .text).notNull().indexed()
                t.column("timestamp", .datetime).notNull()
                t.column("status", .integer).notNull()
                t.column("latencyMs", .double).notNull()
                t.column("ok", .boolean).notNull()
                t.column("error", .text)
            }
        }
    }

    static func history(_ id: UUID, limit: Int = 60) -> [APICheck] {
        (AppDatabase.shared.read {
            try APICheck.filter(Column("endpointId") == id.uuidString).order(Column("timestamp").desc).limit(limit).fetchAll($0)
        } ?? []).reversed()
    }

    static func record(_ c: APICheck) {
        AppDatabase.shared.write { db in
            try c.insert(db)
            try db.execute(sql: "DELETE FROM api_check WHERE timestamp < ?", arguments: [Date().addingTimeInterval(-7 * 86400)])
        }
    }

    static func uptime(_ id: UUID) -> Double? {
        let h = history(id, limit: 500)
        guard !h.isEmpty else { return nil }
        return Double(h.filter(\.ok).count) / Double(h.count)
    }

    // Endpoints are mirrored here so the background monitor keeps checking when the widget is off-screen.
    static var endpoints: [APIEndpoint] {
        get { (UserDefaults.standard.data(forKey: "api.endpoints")).flatMap { try? JSONDecoder().decode([APIEndpoint].self, from: $0) } ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "api.endpoints") }
    }
}

/// Background pinger with up/down transition alerts.
@MainActor
enum APIHealthMonitor {
    private static var lastRun: [UUID: Date] = [:]
    private static var lastOK: [UUID: Bool] = [:]

    static func start() {
        _ = TickScheduler.shared.subscribe(every: 10) { Task { await tick() } }
    }

    static func tick(force: Bool = false) async {
        let now = Date()
        for ep in APIHealthStore.endpoints where force || now.timeIntervalSince(lastRun[ep.id] ?? .distantPast) >= ep.interval {
            lastRun[ep.id] = now
            let c = await check(ep)
            APIHealthStore.record(c)
            if let prev = lastOK[ep.id], prev != c.ok {
                if c.ok { Notifier.post("\(ep.name) recovered", "HTTP \(c.status) in \(Int(c.latencyMs)) ms") }
                else { Notifier.post("\(ep.name) is down", c.error ?? "HTTP \(c.status)") }
            } else if lastOK[ep.id] == nil && !c.ok {
                Notifier.post("\(ep.name) is down", c.error ?? "HTTP \(c.status)")
            }
            lastOK[ep.id] = c.ok
        }
        WidgetBus.shared.publish(.dataChanged("apihealth"))
    }

    static func check(_ ep: APIEndpoint) async -> APICheck {
        guard let url = URL(string: ep.url) else {
            return APICheck(endpointId: ep.id.uuidString, timestamp: Date(), status: 0, latencyMs: 0, ok: false, error: "Invalid URL")
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: ep.timeout)
        req.httpMethod = ep.method
        let start = Date()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ms = Date().timeIntervalSince(start) * 1000
            return APICheck(endpointId: ep.id.uuidString, timestamp: Date(), status: status, latencyMs: ms, ok: status == ep.expectedStatus)
        } catch {
            return APICheck(endpointId: ep.id.uuidString, timestamp: Date(), status: 0, latencyMs: Date().timeIntervalSince(start) * 1000,
                            ok: false, error: error.localizedDescription)
        }
    }
}
