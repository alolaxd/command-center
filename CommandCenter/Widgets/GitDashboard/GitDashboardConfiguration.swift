import SwiftUI

struct GitDashboardConfiguration: WidgetConfiguration {
    var repos: [String] = []
    var showPRs = true
    var showHeatmap = true
    var commitCount = 5

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Section("Repositories") {
                ForEach(config.repos.indices, id: \.self) { i in
                    HStack {
                        Text((config.wrappedValue.repos[i] as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button { config.wrappedValue.repos.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                }
                Button("Add Repositories…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
                    if p.runModal() == .OK { config.wrappedValue.repos.append(contentsOf: p.urls.map(\.path)) }
                }
            }
            Toggle("Show pull requests (needs token in Settings → Integrations)", isOn: config.showPRs)
            Toggle("Show commit heatmap", isOn: config.showHeatmap)
            Stepper("Recent commits: \(config.wrappedValue.commitCount)", value: config.commitCount, in: 1...20)
        }
    }
}
