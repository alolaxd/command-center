import AppKit
import Foundation
import GRDB

struct InboxItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "inbox_item"
    enum Kind: String, Codable, DatabaseValueConvertible { case text, link, image, audio, file }
    var id: String = UUID().uuidString
    var kind: Kind
    var text: String
    var attachment: String?
    var createdAt = Date()
    var triagedAt: Date?
    var triagedTo: String?

    var isStale: Bool { triagedAt == nil && createdAt < Date().addingTimeInterval(-7 * 86400) }
    var attachmentURL: URL? { attachment.map { AppPaths.attachments.appendingPathComponent($0) } }
}

@MainActor
enum InboxStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("inbox.v1") { db in
            try db.create(table: "inbox_item") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("text", .text).notNull()
                t.column("attachment", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("triagedAt", .datetime)
                t.column("triagedTo", .text)
            }
        }
    }

    static func untriaged() -> [InboxItem] {
        AppDatabase.shared.read { try InboxItem.filter(Column("triagedAt") == nil).order(Column("createdAt").desc).fetchAll($0) } ?? []
    }

    static func recentTriaged(limit: Int = 20) -> [InboxItem] {
        AppDatabase.shared.read { try InboxItem.filter(Column("triagedAt") != nil).order(Column("triagedAt").desc).limit(limit).fetchAll($0) } ?? []
    }

    @discardableResult
    static func add(_ text: String, kind: InboxItem.Kind? = nil, attachment: String? = nil) -> InboxItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = kind ?? (URL(string: trimmed).flatMap { $0.scheme?.hasPrefix("http") == true ? InboxItem.Kind.link : nil } ?? .text)
        let item = InboxItem(kind: k, text: trimmed, attachment: attachment)
        AppDatabase.shared.write { try item.insert($0) }
        WidgetBus.shared.publish(.dataChanged("inbox"))
        return item
    }

    static func addImage(_ image: NSImage, note: String = "Screenshot") {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let name = UUID().uuidString + ".png"
        try? png.write(to: AppPaths.attachments.appendingPathComponent(name))
        add(note, kind: .image, attachment: name)
    }

    static func addFile(_ url: URL) {
        let name = UUID().uuidString + "-" + url.lastPathComponent
        try? FileManager.default.copyItem(at: url, to: AppPaths.attachments.appendingPathComponent(name))
        let isImage = ["png", "jpg", "jpeg", "heic", "gif", "tiff"].contains(url.pathExtension.lowercased())
        add(url.lastPathComponent, kind: isImage ? .image : .file, attachment: name)
    }

    static func markTriaged(_ item: InboxItem, to destination: String) {
        var i = item
        i.triagedAt = Date()
        i.triagedTo = destination
        AppDatabase.shared.write { try i.update($0) }
        WidgetBus.shared.publish(.dataChanged("inbox"))
    }

    static func delete(_ item: InboxItem) {
        if let url = item.attachmentURL { try? FileManager.default.removeItem(at: url) }
        AppDatabase.shared.write { _ = try item.delete($0) }
        WidgetBus.shared.publish(.dataChanged("inbox"))
    }

    static func aiSummary() -> String {
        let items = untriaged()
        guard !items.isEmpty else { return "" }
        return "Inbox (\(items.count) untriaged, \(items.filter(\.isStale).count) older than 7 days):\n" +
            items.prefix(15).map { "- \($0.text.prefix(100))" }.joined(separator: "\n")
    }
}

/// Entry point used by the menu bar capture, the command palette and other widgets.
enum InboxCapture {
    @MainActor static func capture(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        InboxStore.add(text)
        WidgetBus.shared.toast("Captured to Inbox", symbol: "tray.and.arrow.down")
    }
}
