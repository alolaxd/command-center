import CryptoKit
import Foundation
import GRDB

struct NewsItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "news_item"
    var id: String
    var feed: String
    var feedTitle: String
    var title: String
    var link: String
    var published: Date
    var summary: String
    var read = false
    var saved = false
}

@MainActor
enum NewsStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("news.v1") { db in
            try db.create(table: "news_item") { t in
                t.primaryKey("id", .text)
                t.column("feed", .text).notNull().indexed()
                t.column("feedTitle", .text).notNull()
                t.column("title", .text).notNull()
                t.column("link", .text).notNull()
                t.column("published", .datetime).notNull().indexed()
                t.column("summary", .text).notNull()
                t.column("read", .boolean).notNull()
                t.column("saved", .boolean).notNull()
            }
        }
    }

    static func items(feeds: [String], limit: Int = 80) -> [NewsItem] {
        AppDatabase.shared.read { try NewsItem.filter(feeds.contains(Column("feed"))).order(Column("published").desc).limit(limit).fetchAll($0) } ?? []
    }

    static func upsert(_ items: [NewsItem]) {
        AppDatabase.shared.write { db in
            for var i in items {
                if let existing = try NewsItem.fetchOne(db, key: i.id) { i.read = existing.read; i.saved = existing.saved }
                try i.save(db)
            }
            try db.execute(sql: "DELETE FROM news_item WHERE published < ? AND saved = 0", arguments: [Date().addingTimeInterval(-30 * 86400)])
        }
    }

    static func setRead(_ id: String, _ read: Bool = true) {
        AppDatabase.shared.write { try $0.execute(sql: "UPDATE news_item SET read = ? WHERE id = ?", arguments: [read, id]) }
    }

    static func fetch(_ feedURL: String) async -> [NewsItem] {
        guard let url = URL(string: feedURL), let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        let parser = FeedParser(data: data)
        let (title, entries) = parser.parse()
        return entries.map { e in
            let id = SHA256.hash(data: Data((e.link.isEmpty ? e.title : e.link).utf8)).map { String(format: "%02x", $0) }.joined()
            return NewsItem(id: id, feed: feedURL, feedTitle: title.isEmpty ? (url.host ?? feedURL) : title, title: e.title,
                            link: e.link, published: e.date ?? Date(), summary: ReaderExtractor.stripTags(e.summary).prefix(400).description)
        }
    }
}

/// Minimal RSS 2.0 / Atom parser.
final class FeedParser: NSObject, XMLParserDelegate {
    struct Entry { var title = ""; var link = ""; var summary = ""; var date: Date? }
    private let parser: XMLParser
    private var feedTitle = ""
    private var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    init(data: Data) { parser = XMLParser(data: data) }

    func parse() -> (String, [Entry]) {
        parser.delegate = self
        parser.parse()
        return (feedTitle, entries)
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        if name == "item" || name == "entry" { current = Entry() }
        if name == "link", current != nil, let href = attributes["href"], (attributes["rel"] ?? "alternate") == "alternate" { current?.link = href }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if current == nil {
            if name == "title" && feedTitle.isEmpty { feedTitle = t }
            return
        }
        switch name {
        case "title": current?.title = t
        case "link": if !t.isEmpty { current?.link = t }
        case "description", "summary", "content", "content:encoded": if (current?.summary.count ?? 0) < t.count { current?.summary = t }
        case "pubDate", "published", "updated", "dc:date": if current?.date == nil { current?.date = Self.parseDate(t) }
        case "item", "entry": if let c = current { entries.append(c) }; current = nil
        default: break
        }
    }

    static func parseDate(_ s: String) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

/// Reader view: pulls article paragraphs out of a page, dropping scripts, nav and ads.
enum ReaderExtractor {
    static func extract(_ url: URL) async -> (title: String, paragraphs: [String])? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        var html = String(decoding: data, as: UTF8.self)
        for tag in ["script", "style", "nav", "header", "footer", "aside", "form", "noscript", "svg", "figure"] {
            html = html.replacingOccurrences(of: "<\(tag)[\\s\\S]*?</\(tag)>", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        let title = html.range(of: "<title[^>]*>([\\s\\S]*?)</title>", options: [.regularExpression, .caseInsensitive])
            .map { stripTags(String(html[$0])) } ?? url.host ?? ""
        var scope = html
        if let r = html.range(of: "<article[\\s\\S]*?</article>", options: [.regularExpression, .caseInsensitive]) { scope = String(html[r]) }
        guard let re = try? NSRegularExpression(pattern: "<(p|h2|h3|li|blockquote)[^>]*>([\\s\\S]*?)</\\1>", options: [.caseInsensitive]) else { return nil }
        let ns = scope as NSString
        let paragraphs = re.matches(in: scope, range: NSRange(location: 0, length: ns.length)).compactMap { m -> String? in
            let tag = ns.substring(with: m.range(at: 1)).lowercased()
            let text = stripTags(ns.substring(with: m.range(at: 2)))
            guard text.count > (tag == "p" ? 40 : 3) else { return nil }
            return tag.hasPrefix("h") ? "## " + text : tag == "li" ? "- " + text : tag == "blockquote" ? "> " + text : text
        }
        return (title, paragraphs)
    }

    static func stripTags(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = ["&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&#8217;": "’", "&#8216;": "‘", "&#8220;": "“", "&#8221;": "”", "&#8211;": "–", "&#8212;": "—", "&hellip;": "…"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        return t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
