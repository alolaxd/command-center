import SwiftUI

struct WorldClocksConfiguration: WidgetConfiguration {
    var zones: [WorldClocksStore.Zone] = [
        .init(identifier: TimeZone.current.identifier, label: "Local"),
        .init(identifier: "America/New_York", label: ""),
        .init(identifier: "Europe/London", label: ""),
        .init(identifier: "Asia/Tokyo", label: ""),
    ]
    var workStart = 9
    var workEnd = 18
    var showPlanner = true
    var showContacts = false

    static func editor(_ config: Binding<Self>) -> some View { WorldClocksSettings(config: config) }
}

private struct WorldClocksSettings: View {
    @Binding var config: WorldClocksConfiguration
    @State private var query = ""
    var body: some View {
        Form {
            Section("Zones") {
                ForEach($config.zones) { $z in
                    HStack {
                        Text(z.identifier).font(.caption).foregroundStyle(.secondary)
                        TextField("Label", text: $z.label)
                        Button { config.zones.removeAll { $0.id == z.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                TextField("Add city / zone (e.g. Paris, Dubai)", text: $query)
                ForEach(WorldClocksStore.search(query), id: \.self) { id in
                    Button(id) { config.zones.append(.init(identifier: id, label: "")); query = "" }.buttonStyle(.link)
                }
            }
            Stepper("Work day starts \(config.workStart):00", value: $config.workStart, in: 0...23)
            Stepper("Work day ends \(config.workEnd):00", value: $config.workEnd, in: 1...24)
            Toggle("Meeting planner", isOn: $config.showPlanner)
            Toggle("Show contacts in each city (Contacts access)", isOn: $config.showContacts)
        }
    }
}
