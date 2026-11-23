import SwiftUI

struct CustomWidgetConfiguration: WidgetConfiguration {
    var definitionID: String?
    var refreshSeconds: Double = 60

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Widget", selection: config.definitionID) {
                Text("None").tag(String?.none)
                ForEach(CustomWidgetStore.all()) { Text($0.name).tag(Optional($0.id)) }
            }
            Picker("Refresh", selection: config.refreshSeconds) {
                Text("10 s").tag(10.0); Text("1 min").tag(60.0); Text("5 min").tag(300.0)
            }
        }
    }
}
