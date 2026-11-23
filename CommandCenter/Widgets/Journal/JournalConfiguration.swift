import SwiftUI

struct JournalConfiguration: WidgetConfiguration {
    var showPrompts = true
    var autoWeeklySummary = true

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Toggle("Show reflection prompts", isOn: config.showPrompts)
            Toggle("Auto-generate last week's AI summary", isOn: config.autoWeeklySummary)
        }
    }
}
