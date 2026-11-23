import SwiftUI

struct HabitTrackerConfiguration: WidgetConfiguration {
    enum Style: String, Codable, CaseIterable { case grid = "Contribution Grid", week = "This Week" }
    var style: Style = .grid
    var weeks = 16

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Style", selection: config.style) { ForEach(Style.allCases, id: \.self) { Text($0.rawValue) } }
            Stepper("Weeks shown: \(config.wrappedValue.weeks)", value: config.weeks, in: 4...52, step: 4)
        }
    }
}
