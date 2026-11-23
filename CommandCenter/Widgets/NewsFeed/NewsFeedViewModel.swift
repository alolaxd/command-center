import Foundation

@MainActor @Observable
final class NewsFeedViewModel {
    var items: [NewsItem] = []
    var loading = false
    var digest: String?
    var digesting = false
    var reader: (item: NewsItem, title: String, paragraphs: [String])?
    var readerLoading = false

    func load(_ config: NewsFeedConfiguration) {
        items = NewsStore.items(feeds: config.feeds).filter { !config.unreadOnly || !$0.read }
    }

    func refresh(_ config: NewsFeedConfiguration) async {
        loading = true
        await withTaskGroup(of: [NewsItem].self) { group in
            for f in config.feeds { group.addTask { await NewsStore.fetch(f) } }
            for await batch in group { NewsStore.upsert(batch) }
        }
        load(config)
        loading = false
    }

    func open(_ item: NewsItem, config: NewsFeedConfiguration) async {
        NewsStore.setRead(item.id)
        load(config)
        guard let url = URL(string: item.link) else { return }
        readerLoading = true
        reader = (item, item.title, [])
        if let r = await ReaderExtractor.extract(url) { reader = (item, r.title.isEmpty ? item.title : r.title, r.paragraphs) }
        readerLoading = false
    }

    func dailyDigest() async {
        digesting = true
        let today = items.filter { $0.published > Date().addingTimeInterval(-86400) }.prefix(60)
        let list = today.map { "- [\($0.feedTitle)] \($0.title): \($0.summary.prefix(200))" }.joined(separator: "\n")
        do {
            digest = try await AIService.shared.complete(
                system: "You write a crisp daily news digest. Group related stories, use short Markdown sections with bullet points, and finish with 'Worth reading' (3 picks).",
                [AIMessage(role: .user, content: "Here's what happened today in my feeds:\n\(list)")])
        } catch { digest = "⚠️ " + error.localizedDescription }
        digesting = false
    }

    func saveToNotes() {
        guard let r = reader else { return }
        let body = "# \(r.title)\n\nSource: \(r.item.link)\n\n" + r.paragraphs.joined(separator: "\n\n")
        let note = NotesStore.create(title: String(r.title.prefix(80)), body: body)
        WidgetBus.shared.toast("Saved “\(note.title)” to Notes", symbol: "note.text")
    }
}
