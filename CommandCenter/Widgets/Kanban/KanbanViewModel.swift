import Foundation

@MainActor @Observable
final class KanbanViewModel {
    var cards: [KanbanCard] = []

    func load() { cards = KanbanStore.all() }

    func cards(_ column: KanbanColumn, lane: String?) -> [KanbanCard] {
        cards.filter { $0.column == column && (lane == nil || $0.lane == lane) }
    }

    var lanes: [String] { Array(Set(cards.map(\.lane))).sorted { ($0.isEmpty ? "~" : $0) < ($1.isEmpty ? "~" : $1) } }

    func isOverLimit(_ column: KanbanColumn, _ config: KanbanConfiguration) -> Bool {
        guard let limit = config.wipLimits[column.rawValue], limit > 0 else { return false }
        return cards.filter { $0.column == column }.count > limit
    }

    func drop(_ ids: [String], on column: KanbanColumn, lane: String?, before: String? = nil) {
        for id in ids { KanbanStore.move(id, to: column, lane: lane, before: before) }
        load()
    }

    func add(_ title: String, column: KanbanColumn, lane: String) {
        // "Fix login #web" puts the card in the "web" lane.
        var t = title, l = lane
        if let r = title.range(of: #"\s#(\w[\w-]*)$"#, options: .regularExpression) {
            l = String(title[r].dropFirst(2)); t = String(title[..<r.lowerBound])
        }
        KanbanStore.addCard(title: t, column: column, lane: l)
        load()
    }
}
