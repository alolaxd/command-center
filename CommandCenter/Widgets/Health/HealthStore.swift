import Foundation
import GRDB

enum HealthMetric: String, Codable, CaseIterable, DatabaseValueConvertible {
    case steps, activeCalories, exerciseMinutes, standHours, heartRate, sleepHours, water, workouts
    var label: String {
        switch self {
        case .steps: "Steps"; case .activeCalories: "Move (kcal)"; case .exerciseMinutes: "Exercise (min)"
        case .standHours: "Stand (h)"; case .heartRate: "Heart rate (bpm)"; case .sleepHours: "Sleep (h)"
        case .water: "Water (ml)"; case .workouts: "Workouts"
        }
    }
}

struct HealthValue: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "health_value"
    var day: String
    var metric: HealthMetric
    var value: Double
    var source: String     // "manual" or "import"
}

/// Health data for the Mac. macOS apps can't read the Health database without Apple's restricted
/// HealthKit entitlement, so data comes from manual logging and Apple Health exports (export.xml).
@MainActor
enum HealthStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("health.v1") { db in
            try db.create(table: "health_value") { t in
                t.column("day", .text).notNull()
                t.column("metric", .text).notNull()
                t.column("value", .double).notNull()
                t.column("source", .text).notNull()
                t.primaryKey(["day", "metric", "source"])
            }
        }
    }

    static func values(since: Date) -> [String: [HealthMetric: Double]] {
        let rows = AppDatabase.shared.read { try HealthValue.filter(Column("day") >= since.dayKey).fetchAll($0) } ?? []
        var out: [String: [HealthMetric: Double]] = [:]
        for r in rows {
            // Heart rate is an average; everything else adds up across sources.
            if r.metric == .heartRate { out[r.day, default: [:]][r.metric] = r.value }
            else { out[r.day, default: [:]][r.metric, default: 0] += r.value }
        }
        return out
    }

    static func add(_ metric: HealthMetric, _ amount: Double, day: Date = Date()) {
        AppDatabase.shared.write { db in
            try db.execute(sql: """
                INSERT INTO health_value (day, metric, value, source) VALUES (?, ?, ?, 'manual')
                ON CONFLICT(day, metric, source) DO UPDATE SET value = value + excluded.value
                """, arguments: [day.dayKey, metric.rawValue, amount])
        }
        if metric == .workouts { HabitStore.signal("health.workout") }
    }

    static func set(_ metric: HealthMetric, _ value: Double, day: String, source: String) {
        AppDatabase.shared.write { try HealthValue(day: day, metric: metric, value: value, source: source).save($0) }
    }

    /// Streams an Apple Health export.xml and aggregates the last `days` days.
    nonisolated static func importExport(_ url: URL, days: Int = 60) async -> (Int, String?) {
        await Task.detached(priority: .utility) {
            let parser = HealthExportParser(cutoff: Date().addingTimeInterval(-Double(days) * 86400))
            guard let xml = XMLParser(contentsOf: url) else { return (0, "Couldn't open \(url.lastPathComponent)") }
            xml.delegate = parser
            xml.shouldResolveExternalEntities = false
            xml.parse()
            let totals = parser.totals
            await MainActor.run {
                for (day, metrics) in totals {
                    for (m, v) in metrics { HealthStore.set(m, m == .heartRate ? v / max(1, parser.hrCount[day] ?? 1) : v, day: day, source: "import") }
                }
                if (totals[Date().dayKey]?[.workouts] ?? 0) > 0 { HabitStore.signal("health.workout") }
            }
            return (totals.count, nil)
        }.value
    }
}

final class HealthExportParser: NSObject, XMLParserDelegate {
    let cutoff: Date
    var totals: [String: [HealthMetric: Double]] = [:]
    var hrCount: [String: Double] = [:]
    private let fmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"; return f }()

    init(cutoff: Date) { self.cutoff = cutoff }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        if name == "Workout", let s = a["startDate"].flatMap(fmt.date(from:)), s >= cutoff {
            totals[s.dayKey, default: [:]][.workouts, default: 0] += 1
            return
        }
        guard name == "Record", let type = a["type"], let start = a["startDate"].flatMap(fmt.date(from:)), start >= cutoff else { return }
        let day = start.dayKey
        let value = Double(a["value"] ?? "") ?? 0
        switch type {
        case "HKQuantityTypeIdentifierStepCount": totals[day, default: [:]][.steps, default: 0] += value
        case "HKQuantityTypeIdentifierActiveEnergyBurned": totals[day, default: [:]][.activeCalories, default: 0] += value
        case "HKQuantityTypeIdentifierAppleExerciseTime": totals[day, default: [:]][.exerciseMinutes, default: 0] += value
        case "HKCategoryTypeIdentifierAppleStandHour": if a["value"]?.hasSuffix("Stood") == true { totals[day, default: [:]][.standHours, default: 0] += 1 }
        case "HKQuantityTypeIdentifierDietaryWater": totals[day, default: [:]][.water, default: 0] += value
        case "HKQuantityTypeIdentifierHeartRate":
            totals[day, default: [:]][.heartRate, default: 0] += value
            hrCount[day, default: 0] += 1
        case "HKCategoryTypeIdentifierSleepAnalysis":
            if a["value"]?.contains("Asleep") == true, let end = a["endDate"].flatMap(fmt.date(from:)) {
                totals[end.dayKey, default: [:]][.sleepHours, default: 0] += end.timeIntervalSince(start) / 3600
            }
        default: break
        }
    }
}
