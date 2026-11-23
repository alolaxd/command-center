import Foundation
import GRDB

struct Snippet: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "snippet"
    var id: String = UUID().uuidString
    var title: String
    var language: String
    var code: String
    var tags: String = ""
    var createdAt = Date()
    var useCount = 0

    var tagList: [String] { tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
}

@MainActor
enum SnippetStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("snippets.v1") { db in
            try db.create(table: "snippet") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("language", .text).notNull()
                t.column("code", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("useCount", .integer).notNull()
            }
            try db.create(virtualTable: "snippet_fts", using: FTS5()) { t in
                t.synchronize(withTable: "snippet")
                t.column("title"); t.column("code"); t.column("tags")
            }
        }
    }

    static func all() -> [Snippet] {
        AppDatabase.shared.read { try Snippet.order(Column("useCount").desc, Column("createdAt").desc).fetchAll($0) } ?? []
    }

    static func search(_ q: String) -> [Snippet] {
        guard let pattern = FTS5Pattern(matchingAllPrefixesIn: q) else { return all() }
        return AppDatabase.shared.read { db in
            try Snippet.fetchAll(db, sql: "SELECT snippet.* FROM snippet JOIN snippet_fts ON snippet_fts.rowid = snippet.rowid WHERE snippet_fts MATCH ? ORDER BY rank", arguments: [pattern])
        } ?? []
    }

    static func save(_ s: Snippet) { AppDatabase.shared.write { try s.save($0) } }
    static func delete(_ s: Snippet) { AppDatabase.shared.write { _ = try s.delete($0) } }
    static func used(_ s: Snippet) { AppDatabase.shared.write { try $0.execute(sql: "UPDATE snippet SET useCount = useCount + 1 WHERE id = ?", arguments: [s.id]) } }

    @discardableResult
    static func importText(_ code: String, title: String? = nil) -> Snippet {
        let lang = LanguageDetector.detect(code)
        let firstLine = code.split(separator: "\n").first.map(String.init) ?? "Snippet"
        let s = Snippet(title: title ?? String(firstLine.prefix(50)), language: lang, code: code)
        save(s)
        return s
    }
}

/// Heuristic language detection for imported code.
enum LanguageDetector {
    static let languages = ["swift", "python", "javascript", "typescript", "shell", "ruby", "go", "rust", "sql", "json", "html", "css", "c", "java", "yaml", "text"]

    static func detect(_ code: String) -> String {
        let c = code
        func has(_ p: String) -> Bool { c.range(of: p, options: .regularExpression) != nil }
        if has(#"^\s*[\{\[]"#) && (try? JSONSerialization.jsonObject(with: Data(c.utf8))) != nil { return "json" }
        if has(#"^#!.*\b(ba|z)?sh\b"#) || has(#"(^|\n)\s*(echo|export|sudo|brew|cd|ls|grep|git) "#) { return "shell" }
        if has(#"\bfunc \w+\(.*\)|\blet \w+\s*[:=]|\bguard let\b|import (SwiftUI|Foundation)"#) { return "swift" }
        if has(#"\bdef \w+\(.*\):|^\s*import \w+$|\bprint\(|\bself\."#) && !has(#"[;{]\s*$"#) { return "python" }
        if has(#"\binterface \w+|: (string|number|boolean)\b|\btype \w+ ="#) { return "typescript" }
        if has(#"\b(const|let|var) \w+ = |=>|function\s*\w*\(|console\.log"#) { return "javascript" }
        if has(#"\bfn \w+\(|\blet mut\b|impl \w+"#) { return "rust" }
        if has(#"\bfunc \w+\(.*\) .*\{|package main|:= "#) { return "go" }
        if has(#"(?i)\b(select|insert into|update|create table)\b.*\b(from|values|set|\()"#) { return "sql" }
        if has(#"<(html|div|span|body|head)\b"#) { return "html" }
        if has(#"^[\w\.#-]+\s*\{[^}]*:[^}]*\}"#) { return "css" }
        if has(#"\bpublic (static )?(class|void)\b"#) { return "java" }
        if has(#"#include <"#) { return "c" }
        if has(#"\bdef \w+|\bend$|\bputs\b"#) { return "ruby" }
        if has(#"^\w[\w-]*:\s"#) { return "yaml" }
        return "text"
    }
}
