import SwiftUI

struct CustomAgent: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var pid: Int32?
    var logPath: String = ""
}

struct AgentMonitorConfiguration: WidgetConfiguration {
    var aiderRepos: [String] = []
    var customAgents: [CustomAgent] = []
    var showHistory = true

    /// Aider repos are needed by the background scanner, so they are mirrored to UserDefaults.
    static var sharedAiderRepos: [String] { UserDefaults.standard.stringArray(forKey: "agents.aiderRepos") ?? [] }

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Toggle("Show session history", isOn: config.showHistory)
            Section("Aider repositories") {
                ForEach(config.aiderRepos.indices, id: \.self) { i in
                    HStack {
                        Text(config.wrappedValue.aiderRepos[i]).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button { config.wrappedValue.aiderRepos.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("Add Folder…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { config.wrappedValue.aiderRepos.append(u.path) }
                }
            }
            Section("Custom agents (by PID or log file)") {
                ForEach(config.customAgents) { $agent in
                    VStack(alignment: .leading) {
                        HStack {
                            TextField("Name", text: $agent.name)
                            Button { config.wrappedValue.customAgents.removeAll { $0.id == agent.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                        }
                        TextField("PID", value: $agent.pid, format: .number.grouping(.never))
                        TextField("Log path", text: $agent.logPath)
                    }
                }
                Button("Add Custom Agent") { config.wrappedValue.customAgents.append(CustomAgent(name: "My agent")) }
            }
        }
    }
}
