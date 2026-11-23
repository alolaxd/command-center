import SwiftUI

struct NotesWidget: DashboardWidget {
    static let kind = "notes"
    static let title = "Notes"
    static let symbol = "note.text"
    static let summary = "Markdown notes with live preview, [[wiki links]], backlinks, tags, smart folders and full-text search."
    static let category = WidgetCategory.productivity
    static let minSize = GridSize(3, 3)
    static let defaultSize = GridSize(6, 4)

    let context: WidgetContext<NotesConfiguration>
    @State private var vm = NotesViewModel()
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var layout: NotesConfiguration.Layout?

    init(context: WidgetContext<NotesConfiguration>) { self.context = context }

    var body: some View {
        HStack(spacing: 8) {
            if context.config.showList && context.size.w >= 4 { sidebar.frame(width: 170) ; Divider() }
            editorArea
        }
        .onAppear { vm.load() }
        .onDisappear { vm.flush() }
        .onReceive(WidgetBus.shared.events) { e in
            if case .saveNote(let title, let body) = e { _ = NotesStore.create(title: title, body: body); vm.load() }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SearchField(text: $vm.query, prompt: "Search notes")
                Button { vm.newNote() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.borderless).help("New note")
            }
            Picker("", selection: $vm.filter) {
                Text("All Notes").tag(NotesViewModel.Filter.all)
                ForEach(context.config.smartFolders) { Text("▸ " + $0.name).tag(NotesViewModel.Filter.smart($0)) }
                ForEach(vm.allTags, id: \.self) { Text("#" + $0).tag(NotesViewModel.Filter.tag($0)) }
            }
            .labelsHidden()
            List(vm.visible, selection: Binding(get: { vm.selectedTitle }, set: { vm.select($0) })) { note in
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title).font(.callout).lineLimit(1)
                    Text(note.modified.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                }
                .tag(note.title)
                .contextMenu {
                    Button("Rename…") { vm.select(note.title); newTitle = note.title; renaming = true }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([note.url]) }
                    Button("Delete", role: .destructive) { NotesStore.delete(note); vm.selectedTitle = nil; vm.load() }
                }
            }
            .listStyle(.plain)
        }
        .alert("Rename Note", isPresented: $renaming) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let n = vm.selected { vm.flush(); NotesStore.rename(n, to: newTitle); vm.selectedTitle = newTitle; vm.load(); vm.select(newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private var editorArea: some View {
        let mode = layout ?? context.config.layout
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(vm.selectedTitle ?? "No note").font(.callout.weight(.semibold)).lineLimit(1)
                if let n = vm.selected, !n.tags.isEmpty {
                    Text(n.tags.map { "#" + $0 }.joined(separator: " ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Picker("", selection: Binding(get: { mode }, set: { layout = $0 })) {
                    Image(systemName: "pencil").tag(NotesConfiguration.Layout.edit)
                    Image(systemName: "rectangle.split.2x1").tag(NotesConfiguration.Layout.split)
                    Image(systemName: "eye").tag(NotesConfiguration.Layout.preview)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                if !(context.config.showList && context.size.w >= 4) {
                    Button { vm.newNote() } label: { Image(systemName: "square.and.pencil") }.buttonStyle(.borderless)
                }
            }
            if vm.selected != nil {
                HStack(spacing: 8) {
                    if mode != .preview {
                        TextEditor(text: Binding(get: { vm.draft }, set: { vm.edit($0) }))
                            .font(.system(.callout, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .accessibilityLabel("Note editor")
                    }
                    if mode == .split { Divider() }
                    if mode != .edit {
                        ScrollView { MarkdownView(text: vm.draft) { vm.openWikiLink($0) }.padding(.trailing, 4) }
                    }
                }
                let backlinks = NotesStore.backlinks(to: vm.selectedTitle ?? "", in: vm.notes)
                if !backlinks.isEmpty {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.left").font(.caption).foregroundStyle(.secondary)
                        Text("Backlinks:").font(.caption).foregroundStyle(.secondary)
                        ForEach(backlinks) { b in
                            Button(b.title) { vm.select(b.title) }.buttonStyle(.link).font(.caption)
                        }
                    }
                }
            } else {
                EmptyStateView(symbol: "note.text", title: "No note selected", action: ("New Note", { vm.newNote() }))
            }
        }
    }
}
