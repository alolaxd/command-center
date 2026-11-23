import SwiftUI

struct NowPlayingConfiguration: WidgetConfiguration {
    var showHistory = true
    static func editor(_ config: Binding<Self>) -> some View {
        Form { Toggle("Show recently played", isOn: config.showHistory) }
    }
}
