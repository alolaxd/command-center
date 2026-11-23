import SwiftUI

struct CountdownConfiguration: WidgetConfiguration {
    var showCompleted = false
    static func editor(_ config: Binding<Self>) -> some View {
        Form { Toggle("Show finished countdowns", isOn: config.showCompleted) }
    }
}
