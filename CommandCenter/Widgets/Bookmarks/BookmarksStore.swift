import AppKit
import Foundation
import GRDB

struct Bookmark: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "bookmark"
    var id: String = UUID().uuidString
    var title: String
    var url: String
    var folder: String = ""
    var tags: String = ""
    var position: Double = 0
    var status: Int?          // last HTTP status (0 = unreachable)
    var checkedAt: Date?

    var isDead: Bool { status.map { $0 == 0 || $0 >= 400 } ?? false }
    var host: String { URL(string: url)?.host ?? url }
}

@MainActor
enum BookmarksStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("bookmarks.v1") { db in
            try db.create(table: "bookmark") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("url", .text).notNull()
                t.column("folder", .text).notNull()
                t.column("tags", .text).notNull()
                t.column("position", .double).notNull()
                t.column("status", .integer)
                t.column("checkedAt", .datetime)
            }
        }
    }

    static func all() -> [Bookmark] { AppDatabase.shared.read { try Bookmark.order(Column("position")).fetchAll($0) } ?? [] }
    static func save(_ b: Bookmark) { AppDatabase.shared.write { try b.save($0) } }
    static func delete(_ b: Bookmark) { AppDatabase.shared.write { _ = try b.delete($0) } }

    static func add(url: String, title: String? = nil, folder: String = "") {
        let u = url.hasPrefix("http") ? url : "https://" + url
        let pos = (all().map(\.position).max() ?? 0) + 1
        save(Bookmark(title: title ?? (URL(string: u)?.host ?? u), url: u, folder: folder, position: pos))
    }

    static func reorder(_ ids: [String]) {
        AppDatabase.shared.write { db in
            for (i, id) in ids.enumerated() { try db.execute(sql: "UPDATE bookmark SET position = ? WHERE id = ?", arguments: [i, id]) }
        }
    }

    // MARK: Favicons (fetched from the site itself, cached on disk)
    static func faviconURL(_ host: String) -> URL { AppPaths.folder("Favicons").appendingPathComponent(host + ".png") }

    static func favicon(for b: Bookmark) async -> NSImage? {
        let file = faviconURL(b.host)
        if let img = NSImage(contentsOf: file) { return img }
        guard let site = URL(string: b.url), let scheme = site.scheme, let host = site.host else { return nil }
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            if let u = URL(string: "\(scheme)://\(host)\(path)"), let (data, resp) = try? await URLSession.shared.data(from: u),
               (resp as? HTTPURLResponse)?.statusCode == 200, let img = NSImage(data: data),
               let tiff = img.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try? png.write(to: file)
                return img
            }
        }
        return nil
    }

    // MARK: Import
    static func importChrome() -> Int {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Bookmarks")
        guard let data = try? Data(contentsOf: path), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = obj["roots"] as? [String: Any] else { return 0 }
        var count = 0
        func walk(_ node: [String: Any], folder: String) {
            if node["type"] as? String == "url", let url = node["url"] as? String {
                add(url: url, title: node["name"] as? String, folder: folder); count += 1
            }
            for child in node["children"] as? [[String: Any]] ?? [] {
                walk(child, folder: node["type"] as? String == "folder" ? (node["name"] as? String ?? folder) : folder)
            }
        }
        for (_, root) in roots { if let r = root as? [String: Any] { walk(r, folder: "Chrome") } }
        return count
    }

    /// Safari's Bookmarks.plist requires Full Disk Access.
    static func importSafari() -> Int? {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari/Bookmarks.plist")
        guard let data = try? Data(contentsOf: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        var count = 0
        func walk(_ node: [String: Any], folder: String) {
            if node["WebBookmarkType"] as? String == "WebBookmarkTypeLeaf", let url = node["URLString"] as? String {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String
                add(url: url, title: title, folder: folder); count += 1
            }
            let name = node["Title"] as? String ?? folder
            for child in node["Children"] as? [[String: Any]] ?? [] { walk(child, folder: name.hasPrefix("com.apple") ? "Safari" : name) }
        }
        walk(plist, folder: "Safari")
        return count
    }

    // MARK: Link health
    static func check(_ b: Bookmark) async -> Bookmark {
        var x = b
        guard let url = URL(string: b.url) else { x.status = 0; return x }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "HEAD"
        var status = (try? await URLSession.shared.data(for: req)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
        if status == 405 || status == 403 {   // some servers reject HEAD
            req.httpMethod = "GET"
            status = (try? await URLSession.shared.data(for: req)).flatMap { ($0.1 as? HTTPURLResponse)?.statusCode } ?? 0
        }
        x.status = status
        x.checkedAt = Date()
        return x
    }
}
