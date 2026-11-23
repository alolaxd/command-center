import Foundation

@MainActor @Observable
final class CountdownViewModel {
    var items: [Countdown] = []
    var now = Date()

    func load(_ config: CountdownConfiguration) {
        now = Date()
        items = CountdownStore.all().filter { config.showCompleted || $0.target > now.addingTimeInterval(-86400) }
    }

    func add(_ text: String, config: CountdownConfiguration) -> Bool {
        guard let c = CountdownStore.parse(text) else { return false }
        CountdownStore.save(c)
        load(config)
        return true
    }
}
