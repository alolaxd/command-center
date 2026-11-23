import Foundation
import GRDB
import IOKit
import IOKit.ps

struct BatteryInfo: Sendable, Equatable {
    var present = false
    var percent = 0
    var isCharging = false
    var onAC = false
    var timeRemaining: Int?      // minutes (to empty or to full)
    var cycleCount: Int?
    var temperature: Double?     // °C
    var health: Double?          // 0…1 (max capacity / design capacity)
    var condition: String?
    var adapterWatts: Int?
}

struct BatterySample: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "battery_sample"
    var timestamp: Date
    var percent: Int
    var charging: Bool
}

@MainActor
enum BatteryStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("battery.v1") { db in
            try db.create(table: "battery_sample") { t in
                t.column("timestamp", .datetime).notNull().indexed()
                t.column("percent", .integer).notNull()
                t.column("charging", .boolean).notNull()
            }
        }
    }

    nonisolated static func read() -> BatteryInfo {
        var info = BatteryInfo()
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for ps in list {
                guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                      d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                info.present = true
                let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
                let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
                info.percent = max > 0 ? cur * 100 / max : cur
                info.isCharging = d[kIOPSIsChargingKey] as? Bool ?? false
                info.onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
                let t = info.isCharging ? d[kIOPSTimeToFullChargeKey] as? Int : d[kIOPSTimeToEmptyKey] as? Int
                info.timeRemaining = (t ?? -1) > 0 ? t : nil
                info.condition = d["BatteryHealth"] as? String
            }
        }
        if let adapter = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] {
            info.adapterWatts = adapter[kIOPSPowerAdapterWattsKey] as? Int
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func prop(_ key: String) -> Any? { IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() }
            info.cycleCount = prop("CycleCount") as? Int
            if let t = prop("Temperature") as? Int { info.temperature = Double(t) / 100 }
            let design = prop("DesignCapacity") as? Int
            let maxRaw = (prop("AppleRawMaxCapacity") as? Int) ?? (prop("NominalChargeCapacity") as? Int)
            if let design, let maxRaw, design > 0 { info.health = min(1, Double(maxRaw) / Double(design)) }
        }
        return info
    }

    static func record() {
        let b = read()
        guard b.present else { return }
        AppDatabase.shared.write { db in
            try BatterySample(timestamp: Date(), percent: b.percent, charging: b.isCharging).insert(db)
            try db.execute(sql: "DELETE FROM battery_sample WHERE timestamp < ?", arguments: [Date().addingTimeInterval(-14 * 86400)])
        }
    }

    static func samples(since: Date) -> [BatterySample] {
        AppDatabase.shared.read { try BatterySample.filter(Column("timestamp") >= since).order(Column("timestamp")).fetchAll($0) } ?? []
    }

    /// Records a sample every 5 minutes for the charge-history graph.
    static func startHistory() {
        _ = TickScheduler.shared.subscribe(every: 300) { record() }
    }
}
