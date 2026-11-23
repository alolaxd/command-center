import SwiftUI

struct TerminalPane: Codable, Hashable, Identifiable {
    var id = UUID()
    var cwd: String = ""
}

struct TerminalTab: Codable, Hashable, Identifiable {
    enum Split: String, Codable { case none, horizontal, vertical }
    var id = UUID()
    var title = ""
    var split: Split = .none
    var panes: [TerminalPane] = [TerminalPane()]
}

struct TerminalPanesConfiguration: WidgetConfiguration {
    var tabs: [TerminalTab] = [TerminalTab()]
    var selected: UUID?
    var fontSize: Double = 12
    var startDirectory = "~"

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            TextField("Start directory for new tabs", text: config.startDirectory)
            Stepper("Font size: \(Int(config.wrappedValue.fontSize))", value: config.fontSize, in: 9...20)
            Text("Font size applies to newly opened panes.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
