import Foundation

@MainActor @Observable
final class AIChatViewModel {
    var messages: [ChatMessage] = []
    var input = ""
    var streaming = ""
    var isRunning = false
    var conversation = ""
    @ObservationIgnored private var task: Task<Void, Never>?

    func load(_ id: UUID) {
        conversation = id.uuidString
        messages = AIChatStore.messages(conversation)
    }

    func send(_ config: AIChatConfiguration, text: String? = nil) {
        let q = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !isRunning else { return }
        input = ""
        let user = ChatMessage(conversation: conversation, role: "user", content: q)
        AIChatStore.append(user)
        messages.append(user)
        isRunning = true
        streaming = ""
        task = Task {
            var system = config.includeData ? AIDataContext.systemPrompt + "\n\n<data_snapshot>\n" + (await AIDataContext.snapshot()) + "\n</data_snapshot>" : "You are a helpful assistant inside a macOS productivity dashboard."
            if !config.systemPrompt.isEmpty { system += "\n\n" + config.systemPrompt }
            let history = messages.suffix(20).map { AIMessage(role: $0.role == "user" ? .user : .assistant, content: $0.content) }
            do {
                for try await chunk in AIService.shared.stream(system: system, Array(history)) { streaming += chunk }
            } catch is CancellationError {
            } catch {
                streaming += (streaming.isEmpty ? "" : "\n\n") + "⚠️ " + error.localizedDescription
            }
            let reply = ChatMessage(conversation: conversation, role: "assistant", content: streaming)
            AIChatStore.append(reply)
            messages.append(reply)
            streaming = ""
            isRunning = false
        }
    }

    func stop() { task?.cancel() }

    func clear() {
        AIChatStore.clear(conversation)
        messages = []
    }
}
