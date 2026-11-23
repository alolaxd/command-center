import Foundation
import GRDB

struct BudgetTransaction: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "budget_txn"
    var id: String = UUID().uuidString
    var amount: Double          // positive = expense, negative = income/refund
    var category: String
    var date: Date
    var note: String = ""
    var recurringId: String?
}

struct BudgetCategory: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "budget_category"
    var id: String { name }
    var name: String
    var monthlyBudget: Double
    var color: String = "blue"
}

struct RecurringExpense: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "budget_recurring"
    var id: String = UUID().uuidString
    var amount: Double
    var category: String
    var dayOfMonth: Int
    var note: String
    var startDate = Calendar.current.startOfDay(for: Date())
}

@MainActor
enum BudgetStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("budget.v1") { db in
            try db.create(table: "budget_txn") { t in
                t.primaryKey("id", .text)
                t.column("amount", .double).notNull()
                t.column("category", .text).notNull()
                t.column("date", .datetime).notNull().indexed()
                t.column("note", .text).notNull()
                t.column("recurringId", .text)
            }
            try db.create(table: "budget_category") { t in
                t.primaryKey("name", .text)
                t.column("monthlyBudget", .double).notNull()
                t.column("color", .text).notNull()
            }
            try db.create(table: "budget_recurring") { t in
                t.primaryKey("id", .text)
                t.column("amount", .double).notNull()
                t.column("category", .text).notNull()
                t.column("dayOfMonth", .integer).notNull()
                t.column("note", .text).notNull()
                t.column("startDate", .datetime).notNull()
            }
            for (name, budget, color) in [("Groceries", 400.0, "green"), ("Dining", 200.0, "orange"), ("Transport", 150.0, "blue"),
                                          ("Subscriptions", 60.0, "purple"), ("Housing", 1500.0, "gray"), ("Fun", 150.0, "pink")] {
                try BudgetCategory(name: name, monthlyBudget: budget, color: color).insert(db)
            }
        }
    }

    static func categories() -> [BudgetCategory] {
        AppDatabase.shared.read { try BudgetCategory.order(Column("name")).fetchAll($0) } ?? []
    }

    static func transactions(in month: Date) -> [BudgetTransaction] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else { return [] }
        return AppDatabase.shared.read {
            try BudgetTransaction.filter(Column("date") >= interval.start && Column("date") < interval.end).order(Column("date").desc).fetchAll($0)
        } ?? []
    }

    static func recurring() -> [RecurringExpense] { AppDatabase.shared.read { try RecurringExpense.fetchAll($0) } ?? [] }

    static func save(_ t: BudgetTransaction) { AppDatabase.shared.write { try t.save($0) } }
    static func delete(_ t: BudgetTransaction) { AppDatabase.shared.write { _ = try t.delete($0) } }
    static func save(_ c: BudgetCategory) { AppDatabase.shared.write { try c.save($0) } }
    static func save(_ r: RecurringExpense) { AppDatabase.shared.write { try r.save($0) }; populateRecurring() }
    static func delete(_ r: RecurringExpense) { AppDatabase.shared.write { _ = try r.delete($0) } }

    /// "12.50 coffee dining" or "-2000 salary" → transaction. Category matched by name prefix, else "Other".
    @discardableResult
    static func quickAdd(_ text: String) -> BudgetTransaction? {
        let parts = text.split(separator: " ").map(String.init)
        guard let first = parts.first, let amount = Double(first.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: ".")) else { return nil }
        let cats = categories().map(\.name)
        var category = "Other"
        var noteParts: [String] = []
        for p in parts.dropFirst() {
            if let c = cats.first(where: { $0.lowercased().hasPrefix(p.lowercased()) && p.count >= 3 }), category == "Other" { category = c }
            else { noteParts.append(p) }
        }
        let t = BudgetTransaction(amount: amount, category: category, date: Date(), note: noteParts.joined(separator: " "))
        save(t)
        return t
    }

    /// Materializes recurring expenses for every month up to today (idempotent).
    static func populateRecurring(now: Date = Date()) {
        let cal = Calendar.current
        AppDatabase.shared.write { db in
            for r in try RecurringExpense.fetchAll(db) {
                var month = cal.dateInterval(of: .month, for: r.startDate)!.start
                while month <= now {
                    let days = cal.range(of: .day, in: .month, for: month)!.count
                    let due = cal.date(byAdding: .day, value: min(r.dayOfMonth, days) - 1, to: month)!
                    if due >= cal.startOfDay(for: r.startDate) && due <= now {
                        let monthEnd = cal.date(byAdding: .month, value: 1, to: month)!
                        let exists = try BudgetTransaction.filter(Column("recurringId") == r.id && Column("date") >= month && Column("date") < monthEnd).fetchCount(db) > 0
                        if !exists { try BudgetTransaction(amount: r.amount, category: r.category, date: due, note: r.note + " (recurring)", recurringId: r.id).insert(db) }
                    }
                    month = cal.date(byAdding: .month, value: 1, to: month)!
                }
            }
        }
    }

    static func spentByCategory(_ month: Date) -> [String: Double] {
        transactions(in: month).reduce(into: [:]) { $0[$1.category, default: 0] += $1.amount }
    }

    static func aiSummary() -> String {
        let spent = spentByCategory(Date())
        guard !spent.isEmpty else { return "" }
        let cats = Dictionary(uniqueKeysWithValues: categories().map { ($0.name, $0.monthlyBudget) })
        let lines = spent.sorted { $0.value > $1.value }.map { "- \($0.key): \($0.value.currency)" + (cats[$0.key].map { " of \($0.currency) budget" } ?? "") }
        return "Budget this month (expenses by category, highest first):\n" + lines.joined(separator: "\n")
    }
}
