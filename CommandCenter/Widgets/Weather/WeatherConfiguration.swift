import SwiftUI

struct WeatherConfiguration: WidgetConfiguration {
    var place = WeatherStore.Place(name: "London, GB", lat: 51.5085, lon: -0.1257)
    var fahrenheit = false
    var showRadar = true
    var severeAlerts = true

    static func editor(_ config: Binding<Self>) -> some View { WeatherSettingsView(config: config) }
}

private struct WeatherSettingsView: View {
    @Binding var config: WeatherConfiguration
    @State private var query = ""
    @State private var status = ""
    var body: some View {
        Form {
            LabeledContent("Location", value: config.place.name)
            HStack {
                TextField("Search city", text: $query).onSubmit(search)
                Button("Set", action: search)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            Toggle("Fahrenheit", isOn: $config.fahrenheit)
            Toggle("Show radar map", isOn: $config.showRadar)
            Toggle("Severe weather notifications", isOn: $config.severeAlerts)
            Text("Data: Open-Meteo, radar: RainViewer.").font(.caption2).foregroundStyle(.secondary)
        }
    }
    private func search() {
        status = "Searching…"
        Task {
            if let p = await WeatherStore.geocode(query) { config.place = p; status = "" } else { status = "Not found" }
        }
    }
}
