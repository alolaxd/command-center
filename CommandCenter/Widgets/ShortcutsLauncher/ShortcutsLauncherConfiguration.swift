import SwiftUI

struct ShortcutsLauncherConfiguration: WidgetConfiguration {
    var tileSize: Double = 72
    var confirmShell = true
    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Slider(value: config.tileSize, in: 56...110) { Text("Tile size") }
            Toggle("Confirm before running shell scripts", isOn: config.confirmShell)
        }
    }
}
