import Combine
import Foundation

/// Cross-widget events. Widgets publish and subscribe without knowing about each other.
enum BusEvent {
    case toast(String, symbol: String = "bell")
    case pomodoroCompleted(task: String?, minutes: Int)
    case habitSignal(name: String)
    case captureToInbox(String)
    case runInTerminal(String)
    case openAIChat(prompt: String?)
    case saveNote(title: String, body: String)
    case createKanbanCard(title: String)
    case dataChanged(String)
}

final class WidgetBus {
    static let shared = WidgetBus()
    let events = PassthroughSubject<BusEvent, Never>()

    func publish(_ event: BusEvent) {
        if Thread.isMainThread { events.send(event) } else { DispatchQueue.main.async { self.events.send(event) } }
    }

    func toast(_ text: String, symbol: String = "bell") { publish(.toast(text, symbol: symbol)) }
}
