import SwiftUI

struct SnippetLibraryConfiguration: WidgetConfiguration {
    var runOnDrop = false
    var showLineNumbers = false

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Toggle("Show line numbers", isOn: config.showLineNumbers)
            Text("Drag a snippet into any terminal to insert it; use “Run in Terminal” to execute it.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
