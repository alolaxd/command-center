import SwiftUI

@MainActor @Observable
final class MenuBarModel {
    enum Tab: String, CaseIterable, Identifiable {
        case terminal = "Terminal", clipboard = "Clipboard", capture = "Capture", ai = "Ask AI"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .terminal: "terminal"
            case .clipboard: "doc.on.clipboard"
            case .capture: "tray.and.arrow.down"
            case .ai: "sparkles"
            }
        }
    }
    var tab: Tab = .terminal
    var input = ""
    var focusToken = 0
    var paletteOutput: String?
    var history: [String] = []
    var historyIndex: Int?
}

struct MenuBarView: View {
    @Bindable var model: MenuBarModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(MenuBarModel.Tab.allCases) { tab in
                    Button { model.tab = tab; model.focusToken += 1 } label: {
                        Label(tab.rawValue, systemImage: tab.symbol)
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(model.tab == tab ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character("\(MenuBarModel.Tab.allCases.firstIndex(of: tab)! + 1)")), modifiers: [.control])
                    .accessibilityAddTraits(model.tab == tab ? .isSelected : [])
                }
                Spacer()
                Button { StatusItemController.shared.openDashboard() } label: { Image(systemName: "rectangle.grid.2x2") }
                    .buttonStyle(.borderless).help("Open Dashboard").accessibilityLabel("Open Dashboard")
            }
            .padding(8)
            Divider()
            Group {
                switch model.tab {
                case .terminal: QuickTerminalView(model: model)
                case .clipboard: ClipboardRingView(focusToken: model.focusToken)
                case .capture: QuickCaptureView(focusToken: model.focusToken)
                case .ai: QuickAIView(focusToken: model.focusToken)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 660, height: 470)
    }
}

/// Single-line input + real PTY output. Lines starting with ">" run app commands.
struct QuickTerminalView: View {
    @Bindable var model: MenuBarModel
    @FocusState private var inputFocused: Bool
    private var session: TerminalSession { TerminalManager.shared.quick }

    var body: some View {
        VStack(spacing: 0) {
            TerminalHostView(session: session)
                .padding(6)
                .frame(maxHeight: .infinity)
            if let out = model.paletteOutput {
                HStack(alignment: .top) {
                    Image(systemName: "command").foregroundStyle(.secondary)
                    Text(out).font(.callout).textSelection(.enabled).lineLimit(6)
                    Spacer()
                    Button { model.paletteOutput = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(8)
                .background(.quaternary.opacity(0.4))
            }
            Divider()
            HStack(spacing: 6) {
                Image(systemName: model.input.hasPrefix(">") ? "command" : "chevron.right")
                    .foregroundStyle(.secondary).frame(width: 14)
                TextField("Type a shell command, or > for app commands (>new reminder, >start pomodoro, >ask claude …)", text: $model.input)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .focused($inputFocused)
                    .onSubmit(submit)
                    .onKeyPress(.upArrow) { recall(-1); return .handled }
                    .onKeyPress(.downArrow) { recall(1); return .handled }
                    .onKeyPress(.tab) {
                        if model.input.hasPrefix(">"), let c = CommandPalette.completions(for: model.input).first { model.input = c }
                        return .handled
                    }
                if model.input.hasPrefix(">") {
                    Text(CommandPalette.completions(for: model.input).first ?? "").font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                Menu {
                    Button("Clear") { session.clear() }
                    Button("Interrupt (⌃C)") { session.send("\u{03}") }
                    Button("Find…") { session.showFind() }
                    Button("Restart Shell") { session.terminate(); session.start() }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            .padding(8)
        }
        .onAppear { inputFocused = true }
        .onChange(of: model.focusToken) { inputFocused = true }
    }

    private func submit() {
        let line = model.input
        model.input = ""
        guard !line.isEmpty else { session.send("\r"); return }
        model.history.append(line)
        model.historyIndex = nil
        if line.hasPrefix(">") {
            Task {
                let result = await CommandPalette.execute(String(line.dropFirst()))
                model.paletteOutput = result
            }
        } else {
            session.runLine(line)
        }
    }

    private func recall(_ delta: Int) {
        guard !model.history.isEmpty else { return }
        let next = (model.historyIndex ?? model.history.count) + delta
        let clamped = max(0, min(model.history.count, next))
        model.historyIndex = clamped
        model.input = clamped < model.history.count ? model.history[clamped] : ""
    }
}

struct ClipboardRingView: View {
    let focusToken: Int
    @State private var query = ""
    @FocusState private var focused: Bool
    private var clip: ClipboardHistory { .shared }

    var filtered: [ClipboardHistory.Entry] {
        query.isEmpty ? clip.entries : clip.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                SearchField(text: $query, prompt: "Search \(clip.entries.count) clipboard entries").focused($focused)
                Button("Clear") { clip.clear() }.controlSize(.small)
            }
            List {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, entry in
                    HStack(alignment: .top) {
                        Text(idx < 9 ? "⌘\(idx + 1)" : "").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.text.trimmingCharacters(in: .whitespacesAndNewlines)).lineLimit(3).font(.callout.monospaced())
                            Text("\(entry.sourceApp ?? "") · \(entry.date.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button { clip.copy(entry); StatusItemController.shared.close() } label: { Image(systemName: "doc.on.doc") }
                            .buttonStyle(.borderless).help("Copy")
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { clip.paste(entry); StatusItemController.shared.close() }
                    .contextMenu {
                        Button("Paste") { clip.paste(entry); StatusItemController.shared.close() }
                        Button("Copy") { clip.copy(entry) }
                        Button("Send to Inbox") { InboxCapture.capture(entry.text) }
                        Button("Save as Snippet") { WidgetBus.shared.publish(.dataChanged("snippet:" + entry.text)) }
                        Button("Remove", role: .destructive) { clip.remove(entry) }
                    }
                }
            }
            .listStyle(.plain)
            .overlay { if clip.entries.isEmpty { EmptyStateView(symbol: "doc.on.clipboard", title: "Nothing copied yet") } }
            // ⌘1…⌘9 paste
            ForEach(0..<9, id: \.self) { i in
                Button("") { if filtered.indices.contains(i) { clip.paste(filtered[i]); StatusItemController.shared.close() } }
                    .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    .frame(width: 0, height: 0).opacity(0)
            }
        }
        .padding(8)
        .onAppear { focused = true }
        .onChange(of: focusToken) { focused = true }
    }
}

struct QuickCaptureView: View {
    let focusToken: Int
    @State private var text = ""
    @State private var saved = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Capture a thought, link or task. It lands in your Inbox for triage.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.body)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                if saved { Label("Saved to Inbox", systemImage: "checkmark").foregroundStyle(.secondary).font(.callout) }
                Spacer()
                Button("Paste Clipboard") { text += NSPasteboard.general.string(forType: .string) ?? "" }
                Button("Capture") { save() }.keyboardShortcut(.return, modifiers: .command).disabled(text.isEmpty)
            }
        }
        .padding(12)
        .onAppear { focused = true }
        .onChange(of: focusToken) { focused = true; saved = false }
    }

    private func save() {
        InboxCapture.capture(text)
        text = ""
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { StatusItemController.shared.close() }
    }
}

struct QuickAIView: View {
    let focusToken: Int
    @State private var prompt = ""
    @State private var answer = ""
    @State private var running = false
    @State private var useData = true
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Group {
                    if answer.isEmpty {
                        Text("Ask anything. With “Use my data” on, the AI gets a snapshot of your pomodoros, habits, budget, commits, reminders, calendar and agent usage.")
                            .foregroundStyle(.secondary)
                    } else {
                        MarkdownView(text: answer)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                TextField("How many pomodoros did I do this week?", text: $prompt)
                    .textFieldStyle(.roundedBorder).focused($focused).onSubmit(ask)
                Toggle("Use my data", isOn: $useData).toggleStyle(.checkbox)
                Button(running ? "…" : "Ask", action: ask).disabled(prompt.isEmpty || running)
            }
        }
        .padding(12)
        .onAppear { focused = true }
        .onChange(of: focusToken) { focused = true }
    }

    private func ask() {
        guard !prompt.isEmpty else { return }
        let q = prompt
        running = true
        answer = ""
        Task {
            let system = useData ? AIDataContext.systemPrompt + "\n\n" + (await AIDataContext.snapshot()) : nil
            do {
                for try await chunk in AIService.shared.stream(system: system, [AIMessage(role: .user, content: q)]) { answer += chunk }
            } catch { answer = "⚠️ " + error.localizedDescription }
            running = false
        }
    }
}
