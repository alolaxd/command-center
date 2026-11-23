import Foundation
import GRDB

struct ChatMessage: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ai_message"
    var id: String = UUID().uuidString
    var conversation: String
    var role: String
    var content: String
    var createdAt = Date()
}

@MainActor
enum AIChatStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("aichat.v1") { db in
            try db.create(table: "ai_message") { t in
                t.primaryKey("id", .text)
                t.column("conversation", .text).notNull().indexed()
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
        }
    }

    static func messages(_ conversation: String) -> [ChatMessage] {
        AppDatabase.shared.read { try ChatMessage.filter(Column("conversation") == conversation).order(Column("createdAt")).fetchAll($0) } ?? []
    }

    static func append(_ m: ChatMessage) { AppDatabase.shared.write { try m.save($0) } }

    static func clear(_ conversation: String) {
        AppDatabase.shared.write { _ = try ChatMessage.filter(Column("conversation") == conversation).deleteAll($0) }
    }
}
