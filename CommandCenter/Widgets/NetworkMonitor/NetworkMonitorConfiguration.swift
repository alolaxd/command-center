import SwiftUI

struct NetworkMonitorConfiguration: WidgetConfiguration {
    var pingHosts: [String] = ["1.1.1.1", "apple.com"]
    var showConnections = true
    var resolveHosts = true

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            TextField("Ping hosts (comma separated)", text: Binding(
                get: { config.wrappedValue.pingHosts.joined(separator: ", ") },
                set: { config.wrappedValue.pingHosts = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }))
            Toggle("Show active connections", isOn: config.showConnections)
            Toggle("Resolve remote host names", isOn: config.resolveHosts)
            Toggle("Look up public IP", isOn: Binding(get: { UserDefaults.standard.bool(forKey: SettingsKey.publicIPLookup) },
                                                      set: { UserDefaults.standard.set($0, forKey: SettingsKey.publicIPLookup) }))
        }
    }
}
