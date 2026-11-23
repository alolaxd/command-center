import AppKit
import Foundation

@MainActor @Observable
final class BookmarksViewModel {
    var bookmarks: [Bookmark] = []
    var icons: [String: NSImage] = [:]
    var query = ""
    var folder = ""
    var checking = false

    var folders: [String] { Array(Set(bookmarks.map(\.folder))).filter { !$0.isEmpty }.sorted() }

    var visible: [Bookmark] {
        bookmarks.filter { b in
            (folder.isEmpty || b.folder == folder)
                && (query.isEmpty || b.title.localizedCaseInsensitiveContains(query) || b.url.localizedCaseInsensitiveContains(query) || b.tags.localizedCaseInsensitiveContains(query))
        }
    }

    func load() {
        bookmarks = BookmarksStore.all()
        Task { for b in bookmarks where icons[b.host] == nil { if let i = await BookmarksStore.favicon(for: b) { icons[b.host] = i } } }
    }

    func checkLinks() async {
        checking = true
        await withTaskGroup(of: Bookmark.self) { group in
            for b in bookmarks { group.addTask { await BookmarksStore.check(b) } }
            for await b in group { BookmarksStore.save(b) }
        }
        load()
        checking = false
        let dead = bookmarks.filter(\.isDead).count
        WidgetBus.shared.toast(dead == 0 ? "All links healthy" : "\(dead) dead link\(dead == 1 ? "" : "s") found", symbol: "link")
    }

    func move(_ id: String, before target: String) {
        var ids = bookmarks.map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        ids.insert(id, at: ids.firstIndex(of: target) ?? ids.count)
        BookmarksStore.reorder(ids)
        load()
    }
}
