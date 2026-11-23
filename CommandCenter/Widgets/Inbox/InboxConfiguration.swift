import SwiftUI

struct InboxConfiguration: WidgetConfiguration {
    var staleDays = 7
    var showTriaged = false

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Stepper("Flag untriaged after \(config.wrappedValue.staleDays) days", value: config.staleDays, in: 1...30)
            Toggle("Show recently triaged items", isOn: config.showTriaged)
        }
    }
}
