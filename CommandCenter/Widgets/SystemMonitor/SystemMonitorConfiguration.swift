import SwiftUI

struct SystemMonitorConfiguration: WidgetConfiguration {
    enum SortKey: String, Codable, CaseIterable { case cpu = "CPU", memory = "Memory" }
    var sortBy: SortKey = .cpu
    var interval: Double = 2
    var showProcesses = true

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Top processes by", selection: config.sortBy) { ForEach(SortKey.allCases, id: \.self) { Text($0.rawValue) } }
            Picker("Sample every", selection: config.interval) {
                Text("1 s").tag(1.0); Text("2 s").tag(2.0); Text("5 s").tag(5.0)
            }
            Toggle("Show top processes", isOn: config.showProcesses)
        }
    }
}
