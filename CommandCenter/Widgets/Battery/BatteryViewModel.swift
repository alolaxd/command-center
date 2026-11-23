import Foundation

@MainActor @Observable
final class BatteryViewModel {
    var info = BatteryInfo()
    var history: [BatterySample] = []
    private var alerted = false

    func refresh(_ config: BatteryConfiguration) {
        info = BatteryStore.read()
        history = BatteryStore.samples(since: Date().addingTimeInterval(-Double(config.historyHours) * 3600))
        if info.present && !info.onAC && info.percent <= config.lowAlert && !alerted {
            alerted = true
            Notifier.post("Battery low", "\(info.percent)% remaining")
        }
        if info.onAC { alerted = false }
    }
}
