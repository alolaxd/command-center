import SwiftUI

struct AIChatConfiguration: WidgetConfiguration {
    var includeData = true
    var systemPrompt = ""

    static func editor(_ config: Binding<Self>) -> some View {
        Form {
            Toggle("Give the AI a snapshot of my data", isOn: config.includeData)
            TextField("Extra instructions", text: config.systemPrompt, axis: .vertical).lineLimit(2...5)
            LabeledContent("Provider", value: AIService.shared.provider.rawValue)
            LabeledContent("Model", value: AIService.shared.model(for: AIService.shared.provider))
        }
    }
}
