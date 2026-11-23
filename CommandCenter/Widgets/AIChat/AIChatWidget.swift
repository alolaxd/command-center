import SwiftUI

struct AIChatWidget: DashboardWidget {
    static let kind = "aichat"
    static let title = "Ask AI"
    static let symbol = "sparkles"
    static let summary = "Chat with Claude, OpenAI, OpenRouter or Ollama — including questions about your own dashboard data."
    static let category = WidgetCategory.aiDev
    static let defaultSize = GridSize(4, 4)

    let context: WidgetContext<AIChatConfiguration>
    @State private var vm = AIChatViewModel()
    @FocusState private var focused: Bool

    init(context: WidgetContext<AIChatConfiguration>) { self.context = context }

    private let suggestions = ["How many pomodoros did I do this week?", "Show my git commits from yesterday",
                               "What's my top expense category?", "What did I spend on AI agents this week?"]

    var body: some View {
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if vm.messages.isEmpty && vm.streaming.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Ask about your data").font(.callout.weight(.semibold))
                                ForEach(suggestions, id: \.self) { s in
                                    Button(s) { vm.send(context.config, text: s) }.buttonStyle(.link).font(.callout)
                                }
                                if !AIService.shared.isConfigured {
                                    Text("Configure a provider in Settings → AI.").font(.caption).foregroundStyle(.orange)
                                }
                            }
                        }
                        ForEach(vm.messages) { m in bubble(m.role, m.content) }
                        if vm.isRunning { bubble("assistant", vm.streaming.isEmpty ? "…" : vm.streaming).id("streaming") }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: vm.streaming) { proxy.scrollTo("bottom", anchor: .bottom) }
                .onChange(of: vm.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack(spacing: 6) {
                TextField("Message", text: $vm.input, axis: .vertical)
                    .textFieldStyle(.plain).lineLimit(1...4).focused($focused)
                    .onSubmit { vm.send(context.config) }
                    .padding(6).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                if vm.isRunning {
                    Button { vm.stop() } label: { Image(systemName: "stop.circle.fill") }.buttonStyle(.borderless).accessibilityLabel("Stop")
                } else {
                    Button { vm.send(context.config) } label: { Image(systemName: "arrow.up.circle.fill").font(.title3) }
                        .buttonStyle(.borderless).disabled(vm.input.isEmpty).accessibilityLabel("Send")
                }
                Menu {
                    Button("Clear Conversation") { vm.clear() }
                    Button("Copy Last Answer") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(vm.messages.last { $0.role == "assistant" }?.content ?? "", forType: .string)
                    }
                    Button("Save Conversation as Note") {
                        let body = vm.messages.map { "**\($0.role == "user" ? "You" : "AI"):** \($0.content)" }.joined(separator: "\n\n")
                        _ = NotesStore.create(title: "AI chat \(Date().formatted(date: .numeric, time: .omitted))", body: body)
                        WidgetBus.shared.toast("Saved to Notes", symbol: "note.text")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
        }
        .onAppear { vm.load(context.instanceID) }
        .onReceive(WidgetBus.shared.events) { e in
            if case .openAIChat(let prompt) = e {
                focused = true
                if let prompt { vm.send(context.config, text: prompt) }
            }
        }
    }

    private func bubble(_ role: String, _ text: String) -> some View {
        HStack {
            if role == "user" { Spacer(minLength: 30) }
            Group {
                if role == "user" { Text(text).textSelection(.enabled) } else { MarkdownView(text: text) }
            }
            .font(.callout)
            .padding(8)
            .background(role == "user" ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if role != "user" { Spacer(minLength: 30) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role == "user" ? "You" : "AI"): \(text)")
    }
}
