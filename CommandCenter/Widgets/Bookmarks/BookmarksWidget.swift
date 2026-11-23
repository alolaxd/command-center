import SwiftUI

struct BookmarksWidget: DashboardWidget {
    static let kind = "bookmarks"
    static let title = "Bookmarks"
    static let symbol = "bookmark"
    static let summary = "Favicon grid of your links with folders, tags, browser import and a dead-link checker."
    static let category = WidgetCategory.information
    static let defaultSize = GridSize(4, 3)

    let context: WidgetContext<BookmarksConfiguration>
    @State private var vm = BookmarksViewModel()
    @State private var editing: Bookmark?

    init(context: WidgetContext<BookmarksConfiguration>) { self.context = context }

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                SearchField(text: $vm.query, prompt: "Filter links")
                Picker("", selection: $vm.folder) {
                    Text("All").tag("")
                    ForEach(vm.folders, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(maxWidth: 110)
                Menu {
                    Button("Import from Chrome") { let n = BookmarksStore.importChrome(); vm.load(); WidgetBus.shared.toast("Imported \(n) bookmarks") }
                    Button("Import from Safari") {
                        if let n = BookmarksStore.importSafari() { vm.load(); WidgetBus.shared.toast("Imported \(n) bookmarks") }
                        else { WidgetBus.shared.toast("Safari bookmarks need Full Disk Access for Command Center") }
                    }
                    Divider()
                    Button(vm.checking ? "Checking…" : "Check Link Health") { Task { await vm.checkLinks() } }.disabled(vm.checking)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: context.config.tileSize + 10), spacing: 8)], spacing: 10) {
                    ForEach(vm.visible) { b in tile(b) }
                }
            }
            AddField(prompt: "Add URL") { BookmarksStore.add(url: $0, folder: vm.folder); vm.load() }
        }
        .onAppear { vm.folder = context.config.folder; vm.load() }
        .sheet(item: $editing) { b in BookmarkEditor(bookmark: b) { vm.load() } }
    }

    private func tile(_ b: Bookmark) -> some View {
        let size = context.config.tileSize
        return Button { if let u = URL(string: b.url) { NSWorkspace.shared.open(u) } } label: {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06))
                    if let icon = vm.icons[b.host] {
                        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit().padding(size * 0.22)
                    } else {
                        Text(String(b.title.prefix(1)).uppercased()).font(.system(size: size * 0.35, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: size * 0.75, height: size * 0.75)
                .overlay(alignment: .topTrailing) {
                    if b.isDead { Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red).font(.caption).offset(x: 4, y: -4) }
                }
                Text(b.title).font(.caption2).lineLimit(1).frame(width: size)
            }
        }
        .buttonStyle(.plain)
        .help(b.isDead ? "\(b.url) — unreachable (HTTP \(b.status ?? 0))" : b.url)
        .draggable(b.id)
        .dropDestination(for: String.self) { ids, _ in if let id = ids.first { vm.move(id, before: b.id) }; return true }
        .contextMenu {
            Button("Edit…") { editing = b }
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(b.url, forType: .string) }
            Button("Delete", role: .destructive) { BookmarksStore.delete(b); vm.load() }
        }
        .accessibilityLabel("\(b.title)\(b.isDead ? ", dead link" : "")")
    }
}

struct BookmarkEditor: View {
    @State var bookmark: Bookmark
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Title", text: $bookmark.title)
            TextField("URL", text: $bookmark.url)
            TextField("Folder", text: $bookmark.folder)
            TextField("Tags", text: $bookmark.tags)
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { BookmarksStore.save(bookmark); onSave(); dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding().frame(width: 380)
    }
}
