import Foundation

@MainActor @Observable
final class WeatherViewModel {
    var report: WeatherReport?
    var error: String?
    var radarTemplate: String?

    func refresh(_ config: WeatherConfiguration) async {
        do {
            let r = try await WeatherStore.forecast(config.place, fahrenheit: config.fahrenheit)
            report = r
            error = nil
            if config.severeAlerts { alertIfSevere(r, config) }
        } catch { self.error = error.localizedDescription }
        if config.showRadar { radarTemplate = await WeatherStore.radarTileTemplate() }
    }

    private func alertIfSevere(_ r: WeatherReport, _ config: WeatherConfiguration) {
        let key = "weather.alerted.\(Date().dayKey)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let gustLimit = config.fahrenheit ? 45.0 : 70.0
        let today = r.days.first
        if WeatherStore.isSevere(r.code) || today.map({ WeatherStore.isSevere($0.code) || $0.gusts >= gustLimit }) == true {
            UserDefaults.standard.set(true, forKey: key)
            let desc = WeatherStore.describe(today?.code ?? r.code).0
            Notifier.post("Severe weather in \(config.place.name)", "\(desc)\(today.map { ", gusts up to \(Int($0.gusts))" } ?? "")")
        }
    }
}
