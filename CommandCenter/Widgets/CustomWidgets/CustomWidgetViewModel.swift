import Foundation

@MainActor @Observable
final class CustomWidgetViewModel {
    var definition: CustomWidgetDef?
    var result: Result<JSNode, CustomWidgetError>?

    func load(_ config: CustomWidgetConfiguration) {
        definition = config.definitionID.flatMap(CustomWidgetStore.get)
        render()
    }

    func render() {
        guard let d = definition else { result = nil; return }
        result = CustomWidgetStore.render(d.script, widgetID: d.id)
    }
}
