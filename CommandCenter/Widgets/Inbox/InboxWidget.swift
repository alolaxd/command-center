import SwiftUI
import UniformTypeIdentifiers

struct InboxWidget: DashboardWidget {
    static let kind = "inbox"
    static let title = "Inbox"
    static let symbol = "tray.full"
    static let summary = "Universal capture for thoughts, links, screenshots and voice memos, with triage into other widgets."
    static let category = WidgetCategory.productivity
    static let defaultSize = GridSize(3, 4)

    let context: WidgetContext<InboxConfiguration>
    @State private var vm = InboxViewModel()
    @State private var dropTargeted = false

    init(context: WidgetContext<InboxConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                AddField(prompt: "Capture a thought or link…") { InboxStore.add($0); vm.load(context.config) }
                Button { pasteImage() } label: { Image(systemName: "photo.on.rectangle") }
                    .buttonStyle(.borderless).help("Paste screenshot / image from clipboard").accessibilityLabel("Paste image")
                Button { vm.toggleRecording(context.config) } label: {
                    Image(systemName: vm.recording ? "stop.circle.fill" : "mic").foregroundStyle(vm.recording ? .red : .primary)
                }
                .buttonStyle(.borderless).help(vm.recording ? "Stop recording" : "Record voice memo")
                .accessibilityLabel(vm.recording ? "Stop recording" : "Record voice memo")
            }
            let stale = vm.items.filter { vm.isStale($0, context.config) }.count
            if stale > 0 {
                Label("\(stale) item\(stale == 1 ? "" : "s") untriaged for over \(context.config.staleDays) days", systemImage: "flag.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            List {
                ForEach(vm.items) { item in row(item) }
                if !vm.triaged.isEmpty {
                    Section("Recently triaged") {
                        ForEach(vm.triaged) { item in
                            HStack { Text(item.text).lineLimit(1).foregroundStyle(.secondary); Spacer(); Text("→ \(item.triagedTo ?? "")").font(.caption2).foregroundStyle(.tertiary) }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay { if vm.items.isEmpty { EmptyStateView(symbol: "tray", title: "Inbox zero", message: "⌘⇧N captures from anywhere.") } }
        }
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: dropTargeted ? 2 : 0))
        .onDrop(of: [.fileURL, .url, .plainText, .image], isTargeted: $dropTargeted) { providers in handleDrop(providers); return true }
        .onAppear { vm.load(context.config) }
        .onChange(of: context.config) { vm.load(context.config) }
        .onReceive(WidgetBus.shared.events) { e in if case .dataChanged("inbox") = e { vm.load(context.config) } }
    }

    private func row(_ item: InboxItem) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon(item.kind)).foregroundStyle(.secondary).frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                if item.kind == .link, let url = URL(string: item.text) {
                    Link(item.text, destination: url).lineLimit(2).font(.callout)
                } else {
                    Text(item.text).lineLimit(4).font(.callout)
                }
                if item.kind == .image, let url = item.attachmentURL, let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().scaledToFit().frame(maxHeight: 80).clipShape(RoundedRectangle(cornerRadius: 4))
                        .onTapGesture { NSWorkspace.shared.open(url) }
                }
                if item.kind == .audio {
                    Button("Play") { vm.play(item) }.controlSize(.small)
                }
                HStack(spacing: 4) {
                    if vm.isStale(item, context.config) { Image(systemName: "flag.fill").foregroundStyle(.orange) }
                    Text(item.createdAt.formatted(.relative(presentation: .named)))
                    if let s = vm.suggestion[item.id] { Text("· AI: \(s)").lineLimit(2) }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { vm.toReminder(item); vm.load(context.config) } label: { Label("Reminder", systemImage: "checklist") }
                Button { vm.toEvent(item); vm.load(context.config) } label: { Label("Calendar Event", systemImage: "calendar") }
                Button { vm.toNote(item); vm.load(context.config) } label: { Label("Note", systemImage: "note.text") }
                Button { vm.toKanban(item); vm.load(context.config) } label: { Label("Kanban Task", systemImage: "rectangle.split.3x1") }
                Divider()
                Button { Task { await vm.suggest(item) } } label: { Label("Suggest with AI", systemImage: "sparkles") }
                Button(role: .destructive) { InboxStore.delete(item); vm.load(context.config) } label: { Label("Delete", systemImage: "trash") }
            } label: { Text("Triage").font(.caption) }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ k: InboxItem.Kind) -> String {
        switch k { case .text: "text.alignleft"; case .link: "link"; case .image: "photo"; case .audio: "waveform"; case .file: "doc" }
    }

    private func pasteImage() {
        if let img = NSImage(pasteboard: .general) { InboxStore.addImage(img); vm.load(context.config) }
        else { WidgetBus.shared.toast("No image on the clipboard") }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for p in providers {
            if p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in
                        if url.isFileURL { InboxStore.addFile(url) } else { InboxStore.add(url.absoluteString) }
                        vm.load(context.config)
                    }
                }
            } else if p.canLoadObject(ofClass: String.self) {
                _ = p.loadObject(ofClass: String.self) { s, _ in
                    guard let s else { return }
                    Task { @MainActor in InboxStore.add(s); vm.load(context.config) }
                }
            }
        }
    }
}
