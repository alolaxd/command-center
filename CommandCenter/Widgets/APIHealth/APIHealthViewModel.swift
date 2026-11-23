import Foundation

@MainActor @Observable
final class APIHealthViewModel {
    var history: [UUID: [APICheck]] = [:]

    func sync(_ config: APIHealthConfiguration) {
        // Merge this widget's endpoints into the shared monitored set.
        var all = APIHealthStore.endpoints.filter { e in !config.endpoints.contains { $0.id == e.id } }
        all.append(contentsOf: config.endpoints)
        APIHealthStore.endpoints = all
        load(config)
    }

    func load(_ config: APIHealthConfiguration) {
        history = Dictionary(uniqueKeysWithValues: config.endpoints.map { ($0.id, APIHealthStore.history($0.id)) })
    }

    func checkNow(_ config: APIHealthConfiguration) async {
        for ep in config.endpoints { APIHealthStore.record(await APIHealthMonitor.check(ep)) }
        load(config)
    }
}
