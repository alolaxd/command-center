import SwiftUI

struct BatteryConfiguration: WidgetConfiguration {
    var historyHours = 24
    var lowAlert = 20

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("History", selection: config.historyHours) { Text("12 h").tag(12); Text("24 h").tag(24); Text("3 days").tag(72); Text("7 days").tag(168) }
            Stepper("Low battery alert at \(config.wrappedValue.lowAlert)%", value: config.lowAlert, in: 5...50, step: 5)
        }
    }
}
