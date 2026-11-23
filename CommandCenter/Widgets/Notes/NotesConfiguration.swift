import SwiftUI

struct SmartFolder: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Search text, or "#tag" for tag filters.
    var query: String
}

struct NotesConfiguration: WidgetConfiguration {
    enum Layout: String, Codable, CaseIterable { case edit = "Edit", preview = "Preview", split = "Split" }
    var layout: Layout = .split
    var smartFolders: [SmartFolder] = [SmartFolder(name: "Ideas", query: "#idea")]
    var showList = true

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Picker("Editor", selection: config.layout) { ForEach(Layout.allCases, id: \.self) { Text($0.rawValue) } }
            Toggle("Show note list", isOn: config.showList)
            Section("Smart folders") {
                ForEach(config.smartFolders) { $folder in
                    HStack {
                        TextField("Name", text: $folder.name)
                        TextField("Query or #tag", text: $folder.query)
                        Button { config.wrappedValue.smartFolders.removeAll { $0.id == folder.id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                Button("Add Smart Folder") { config.wrappedValue.smartFolders.append(SmartFolder(name: "New", query: "")) }
            }
        }
    }
}
