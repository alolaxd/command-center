import SwiftUI

struct TickerEntry: Codable, Hashable, Identifiable {
    var id = UUID()
    var symbol: String
    var holdings: Double = 0
    var alertAbove: Double?
    var alertBelow: Double?
}

struct TickerConfiguration: WidgetConfiguration {
    var entries: [TickerEntry] = [TickerEntry(symbol: "AAPL"), TickerEntry(symbol: "^GSPC"), TickerEntry(symbol: "crypto:bitcoin")]
    var range: TickerStore.Range = .day
    var showPortfolio = true

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Sparkline range", selection: config.range) { ForEach(TickerStore.Range.allCases, id: \.self) { Text($0.rawValue) } }
            Toggle("Show portfolio value", isOn: config.showPortfolio)
            Section("Watchlist — stocks like AAPL, crypto like crypto:bitcoin") {
                ForEach(config.entries) { $e in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Symbol", text: $e.symbol)
                            Button { config.wrappedValue.entries.removeAll { $0.id == e.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                        HStack {
                            TextField("Holdings", value: $e.holdings, format: .number)
                            TextField("Alert above", value: $e.alertAbove, format: .number)
                            TextField("Alert below", value: $e.alertBelow, format: .number)
                        }
                        .font(.caption)
                    }
                }
                Button("Add Symbol") { config.wrappedValue.entries.append(TickerEntry(symbol: "")) }
            }
        }
    }
}
