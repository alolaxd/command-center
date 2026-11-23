import Foundation

@MainActor @Observable
final class NotesViewModel {
    var notes: [Note] = []
    var selectedTitle: String?
    var draft = ""
    var query = ""
    var filter: Filter = .all
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    enum Filter: Hashable { case all, tag(String), smart(SmartFolder) }

    var selected: Note? { notes.first { $0.title == selectedTitle } }

    var allTags: [String] { Array(Set(notes.flatMap(\.tags))).sorted() }

    var visible: [Note] {
        var list = notes
        switch filter {
        case .all: break
        case .tag(let t): list = list.filter { $0.tags.contains(t) }
        case .smart(let f): list = apply(query: f.query, to: list)
        }
        return query.isEmpty ? list : apply(query: query, to: list)
    }

    private func apply(query: String, to list: [Note]) -> [Note] {
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return list }
        if q.hasPrefix("#") { return list.filter { $0.tags.contains(String(q.dropFirst())) } }
        let ranked = NotesStore.search(q)
        let byTitle = Dictionary(uniqueKeysWithValues: list.map { ($0.title, $0) })
        let hits = ranked.compactMap { byTitle[$0] }
        return hits.isEmpty ? list.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q) } : hits
    }

    func load() {
        notes = NotesStore.all()
        if notes.isEmpty {
            _ = NotesStore.create(title: "Welcome", body: "# Welcome\n\nNotes are **Markdown** files. Link notes with [[Ideas]] and tag them with #idea.\n\n- [ ] Try a task list\n- Search is full-text\n")
            notes = NotesStore.all()
            NotesStore.reindexAll()
        }
        if selectedTitle == nil || selected == nil { select(notes.first?.title) }
    }

    func select(_ title: String?) {
        flush()
        selectedTitle = title
        draft = selected?.body ?? ""
    }

    func edit(_ text: String) {
        draft = text
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        guard let title = selectedTitle, let note = selected, note.body != draft else { return }
        NotesStore.save(title: title, body: draft)
        if let i = notes.firstIndex(where: { $0.title == title }) { notes[i].body = draft; notes[i].modified = Date() }
    }

    func newNote() {
        let n = NotesStore.create(title: "Untitled")
        load()
        select(n.title)
    }

    func openWikiLink(_ title: String) {
        if NotesStore.note(titled: title) == nil { _ = NotesStore.create(title: title) }
        load()
        select(NotesStore.note(titled: title)?.title)
    }
}
