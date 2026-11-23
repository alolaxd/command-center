import SwiftUI

struct ScreenTimeConfiguration: WidgetConfiguration {
    var topCount = 6
    static func editor(_ config: Binding<Self>) -> some View {
        Form { Stepper("Top apps: \(config.wrappedValue.topCount)", value: config.topCount, in: 3...15) }
    }
}
