import SwiftUI

struct APIHealthConfiguration: WidgetConfiguration {
    var endpoints: [APIEndpoint] = []

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            ForEach(config.endpoints) { $ep in
                Section {
                    TextField("Name", text: $ep.name)
                    TextField("URL", text: $ep.url)
                    Picker("Method", selection: $ep.method) { ForEach(["GET", "HEAD", "POST"], id: \.self) { Text($0) } }
                    Stepper("Expect HTTP \(ep.expectedStatus)", value: $ep.expectedStatus, in: 100...599)
                    Picker("Every", selection: $ep.interval) {
                        Text("30 s").tag(30.0); Text("1 min").tag(60.0); Text("5 min").tag(300.0); Text("15 min").tag(900.0)
                    }
                    Button("Remove", role: .destructive) { config.wrappedValue.endpoints.removeAll { $0.id == ep.id } }
                }
            }
            Button("Add Endpoint") { config.wrappedValue.endpoints.append(APIEndpoint(name: "My API", url: "https://")) }
        }
    }
}
