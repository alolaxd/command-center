import SwiftUI

struct SnippetLibraryWidget: DashboardWidget {
    static let kind = "snippets"
    static let title = "Snippets"
    static let symbol = "curlybraces"
    static let summary = "Code snippet library with highlighting, tags, search, clipboard import, AI explain and drag-to-terminal."
    static let category = WidgetCategory.aiDev
    static let minSize = GridSize(3, 3)
    static let defaultSize = GridSize(5, 4)

    let context: WidgetContext<SnippetLibraryConfiguration>
    @State private var vm = SnippetLibraryViewModel()
    @State private var editing: Snippet?

    init(context: WidgetContext<SnippetLibraryConfiguration>) { self.context = context }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 6) {
                HStack {
                    SearchField(text: $vm.query, prompt: "Search code")
                    Menu {
                        Button("New Snippet") { editing = Snippet(title: "New snippet", language: "swift", code: "") }
                        Button("Import from Clipboard") { vm.importClipboard() }
                    } label: { Image(systemName: "plus") }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                }
                Picker("", selection: $vm.language) {
                    Text("All languages").tag("all")
                    ForEach(vm.languages, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                List(vm.visible, selection: Binding(get: { vm.selected?.id }, set: { id in vm.selected = vm.snippets.first { $0.id == id }; vm.explanation = nil })) { s in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.title).font(.callout).lineLimit(1)
                        Text(([s.language] + s.tagList.map { "#" + $0 }).joined(separator: " ")).font(.caption2).foregroundStyle(.secondary)
                    }
                    .tag(s.id)
                    .draggable(s.code)
                    .contextMenu {
                        Button("Copy") { vm.copy(s) }
                        Button("Run in Terminal") { WidgetBus.shared.publish(.runInTerminal(s.code)); SnippetStore.used(s) }
                        Button("Edit…") { editing = s }
                        Button("Delete", role: .destructive) { SnippetStore.delete(s); vm.load() }
                    }
                }
                .listStyle(.plain)
            }
            .frame(width: context.size.w >= 5 ? 180 : nil)
            if context.size.w >= 5, let s = vm.selected { detail(s) }
        }
        .onAppear { vm.load() }
        .onReceive(WidgetBus.shared.events) { e in
            if case .dataChanged(let key) = e, key.hasPrefix("snippet:") {
                SnippetStore.importText(String(key.dropFirst(8))); vm.load()
                WidgetBus.shared.toast("Saved snippet", symbol: "curlybraces")
            }
        }
        .sheet(item: $editing) { s in SnippetEditor(snippet: s) { vm.load(); vm.selected = $0 } }
    }

    private func detail(_ s: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(s.title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Button { vm.copy(s) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help("Copy")
                Button { WidgetBus.shared.publish(.runInTerminal(s.code)); SnippetStore.used(s) } label: { Image(systemName: "play") }
                    .buttonStyle(.borderless).help("Run in terminal")
                Button { Task { await vm.explain(s) } } label: { Image(systemName: "sparkles") }.buttonStyle(.borderless).help("Explain with AI")
                Button { editing = s } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).help("Edit")
            }
            ScrollView([.vertical, .horizontal]) {
                HStack(alignment: .top, spacing: 8) {
                    if context.config.showLineNumbers {
                        Text((1...max(1, s.code.split(separator: "\n", omittingEmptySubsequences: false).count)).map(String.init).joined(separator: "\n"))
                            .foregroundStyle(.tertiary)
                    }
                    Text(SyntaxHighlighter.highlight(s.code, language: s.language)).textSelection(.enabled)
                }
                .font(.system(.callout, design: .monospaced))
                .padding(8)
            }
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .draggable(s.code)
            if let e = vm.explanation {
                ScrollView { MarkdownView(text: e).font(.caption) }.frame(maxHeight: 120)
            }
        }
    }
}

struct SnippetEditor: View {
    @State var snippet: Snippet
    var onSave: (Snippet) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading) {
            Form {
                TextField("Title", text: $snippet.title)
                Picker("Language", selection: $snippet.language) { ForEach(LanguageDetector.languages, id: \.self) { Text($0) } }
                TextField("Tags (comma separated)", text: $snippet.tags)
            }
            TextEditor(text: $snippet.code).font(.system(.callout, design: .monospaced)).frame(minHeight: 200)
                .border(Color.primary.opacity(0.1))
            HStack {
                Button("Detect Language") { snippet.language = LanguageDetector.detect(snippet.code) }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { SnippetStore.save(snippet); onSave(snippet); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding().frame(width: 520, height: 460)
    }
}
