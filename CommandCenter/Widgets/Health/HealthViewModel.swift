import AppKit
import Foundation

@MainActor @Observable
final class HealthViewModel {
    var days: [String: [HealthMetric: Double]] = [:]
    var importing = false

    func load() { days = HealthStore.values(since: Date().addingTimeInterval(-7 * 86400)) }

    var today: [HealthMetric: Double] { days[Date().dayKey] ?? [:] }

    func week(_ m: HealthMetric) -> [Double] {
        (0..<7).reversed().map { days[Date().addingTimeInterval(-Double($0) * 86400).dayKey]?[m] ?? 0 }
    }

    func importExport() async {
        let panel = NSOpenPanel()
        panel.message = "Choose export.xml from an Apple Health export (Health app → profile → Export All Health Data)."
        panel.allowedContentTypes = [.xml]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        let (n, err) = await HealthStore.importExport(url)
        importing = false
        WidgetBus.shared.toast(err ?? "Imported health data for \(n) days", symbol: "heart")
        load()
    }

    func checkStepGoal(_ goal: Double) {
        if (today[.steps] ?? 0) >= goal { HabitStore.signal("health.steps") }
    }
}
