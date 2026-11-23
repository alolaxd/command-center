import Foundation
import GRDB

enum KanbanColumn: String, Codable, CaseIterable, Identifiable, DatabaseValueConvertible {
    case backlog = "Backlog", todo = "To Do", inProgress = "In Progress", review = "Review", done = "Done"
    var id: String { rawValue }
}

enum KanbanLink: Hashable {
    case reminder(String), note(String), repo(String), url(String)
    var type: String { switch self { case .reminder: "reminder"; case .note: "note"; case .repo: "repo"; case .url: "url" } }
    var value: String { switch self { case .reminder(let v), .note(let v), .repo(let v), .url(let v): v } }
    var symbol: String { switch self { case .reminder: "checklist"; case .note: "note.text"; case .repo: "arrow.triangle.branch"; case .url: "link" } }
    init?(type: String?, value: String?) {
        guard let type, let value, !value.isEmpty else { return nil }
        switch type {
        case "reminder": self = .reminder(value)
        case "note": self = .note(value)
        case "repo": self = .repo(value)
        case "url": self = .url(value)
        default: return nil
        }
    }
}

struct KanbanCard: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "kanban_card"
    var id: String = UUID().uuidString
    var title: String
    var details: String = ""
    var column: KanbanColumn = .todo
    var lane: String = ""
    var position: Double = 0
    var linkType: String?
    var linkValue: String?
    var createdAt = Date()
    var completedAt: Date?

    var link: KanbanLink? {
        get { KanbanLink(type: linkType, value: linkValue) }
        set { linkType = newValue?.type; linkValue = newValue?.value }
    }
}

@MainActor
enum KanbanStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("kanban.v1") { db in
            try db.create(table: "kanban_card") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("details", .text).notNull().defaults(to: "")
                t.column("column", .text).notNull()
                t.column("lane", .text).notNull().defaults(to: "")
                t.column("position", .double).notNull()
                t.column("linkType", .text)
                t.column("linkValue", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }
        }
    }

    static func all() -> [KanbanCard] {
        AppDatabase.shared.read { try KanbanCard.order(Column("position")).fetchAll($0) } ?? []
    }

    @discardableResult
    static func addCard(title: String, column: KanbanColumn = .todo, lane: String = "", link: KanbanLink? = nil) -> KanbanCard {
        var card = KanbanCard(title: title, column: column, lane: lane)
        card.link = link
        card.position = (all().filter { $0.column == column }.map(\.position).max() ?? 0) + 1
        AppDatabase.shared.write { try card.insert($0) }
        WidgetBus.shared.publish(.dataChanged("kanban"))
        return card
    }

    static func save(_ card: KanbanCard) {
        var c = card
        if c.column == .done && c.completedAt == nil { c.completedAt = Date() }
        if c.column != .done { c.completedAt = nil }
        AppDatabase.shared.write { try c.save($0) }
        WidgetBus.shared.publish(.dataChanged("kanban"))
    }

    static func move(_ id: String, to column: KanbanColumn, lane: String?, before: String?) {
        var cards = all()
        guard let idx = cards.firstIndex(where: { $0.id == id }) else { return }
        var card = cards.remove(at: idx)
        card.column = column
        if let lane { card.lane = lane }
        let siblings = cards.filter { $0.column == column }
        if let before, let target = siblings.firstIndex(where: { $0.id == before }) {
            let prev = target > 0 ? siblings[target - 1].position : siblings[target].position - 1
            card.position = (prev + siblings[target].position) / 2
        } else {
            card.position = (siblings.map(\.position).max() ?? 0) + 1
        }
        save(card)
    }

    static func delete(_ id: String) {
        AppDatabase.shared.write { _ = try KanbanCard.deleteOne($0, key: id) }
        WidgetBus.shared.publish(.dataChanged("kanban"))
    }

    static func aiSummary() -> String {
        let cards = all()
        guard !cards.isEmpty else { return "" }
        let byCol = KanbanColumn.allCases.map { col in "\(col.rawValue): " + cards.filter { $0.column == col }.map(\.title).prefix(10).joined(separator: "; ") }
        let doneWeek = cards.filter { ($0.completedAt ?? .distantPast) > Date().addingTimeInterval(-7 * 86400) }.count
        return "Kanban board (\(doneWeek) cards completed this week):\n" + byCol.joined(separator: "\n")
    }
}
