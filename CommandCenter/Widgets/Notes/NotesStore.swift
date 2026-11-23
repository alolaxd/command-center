import Foundation
import GRDB

struct Note: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var body: String
    var modified: Date
    var url: URL

    var tags: [String] {
        let re = try! NSRegularExpression(pattern: #"(?<![\w#])#([A-Za-z][\w/-]*)"#)
        return Array(Set(re.matches(in: body, range: NSRange(body.startIndex..., in: body))
            .compactMap { Range($0.range(at: 1), in: body).map { String(body[$0]) } })).sorted()
    }

    var links: [String] {
        let re = try! NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#)
        return re.matches(in: body, range: NSRange(body.startIndex..., in: body))
            .compactMap { Range($0.range(at: 1), in: body).map { String(body[$0]) } }
    }
}

/// Notes are plain Markdown files in ~/Library/Application Support/CommandCenter/Notes.
/// An FTS5 index in SQLite powers full-text search.
@MainActor
enum NotesStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("notes.v1") { db in
            try db.create(virtualTable: "note_fts", using: FTS5()) { t in
                t.tokenizer = .porter(wrapping: .unicode61())
                t.column("title")
                t.column("body")
            }
        }
    }

    static func fileURL(_ title: String) -> URL {
        let safe = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return AppPaths.notes.appendingPathComponent(safe).appendingPathExtension("md")
    }

    static func all() -> [Note] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: AppPaths.notes, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.filter { $0.pathExtension == "md" }.compactMap { url in
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Note(title: url.deletingPathExtension().lastPathComponent, body: body, modified: mod, url: url)
        }
        .sorted { $0.modified > $1.modified }
    }

    static func note(titled title: String) -> Note? { all().first { $0.title.caseInsensitiveCompare(title) == .orderedSame } }

    @discardableResult
    static func save(title: String, body: String) -> Note {
        let url = fileURL(title)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        index(title: title, body: body)
        WidgetBus.shared.publish(.dataChanged("notes"))
        return Note(title: title, body: body, modified: Date(), url: url)
    }

    static func create(title: String, body: String = "") -> Note {
        var name = title.isEmpty ? "Untitled" : title
        var n = 2
        while FileManager.default.fileExists(atPath: fileURL(name).path) { name = "\(title.isEmpty ? "Untitled" : title) \(n)"; n += 1 }
        return save(title: name, body: body.isEmpty ? "# \(name)\n\n" : body)
    }

    static func rename(_ note: Note, to newTitle: String) {
        guard !newTitle.isEmpty, newTitle != note.title else { return }
        try? FileManager.default.moveItem(at: note.url, to: fileURL(newTitle))
        // Update [[links]] in other notes.
        for other in all() where other.body.contains("[[\(note.title)]]") {
            save(title: other.title, body: other.body.replacingOccurrences(of: "[[\(note.title)]]", with: "[[\(newTitle)]]"))
        }
        reindexAll()
    }

    static func delete(_ note: Note) {
        try? FileManager.default.trashItem(at: note.url, resultingItemURL: nil)
        AppDatabase.shared.write { try $0.execute(sql: "DELETE FROM note_fts WHERE title = ?", arguments: [note.title]) }
        WidgetBus.shared.publish(.dataChanged("notes"))
    }

    static func index(title: String, body: String) {
        AppDatabase.shared.write { db in
            try db.execute(sql: "DELETE FROM note_fts WHERE title = ?", arguments: [title])
            try db.execute(sql: "INSERT INTO note_fts (title, body) VALUES (?, ?)", arguments: [title, body])
        }
    }

    static func reindexAll() {
        let notes = all()
        AppDatabase.shared.write { db in
            try db.execute(sql: "DELETE FROM note_fts")
            for n in notes { try db.execute(sql: "INSERT INTO note_fts (title, body) VALUES (?, ?)", arguments: [n.title, n.body]) }
        }
    }

    /// Full-text search; returns matching titles ranked by relevance.
    static func search(_ query: String) -> [String] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: query) else { return [] }
        return AppDatabase.shared.read { db in
            try String.fetchAll(db, sql: "SELECT title FROM note_fts WHERE note_fts MATCH ? ORDER BY rank", arguments: [pattern])
        } ?? []
    }

    static func backlinks(to title: String, in notes: [Note]) -> [Note] {
        notes.filter { $0.title != title && $0.links.contains { $0.caseInsensitiveCompare(title) == .orderedSame } }
    }
}
