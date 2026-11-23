import Foundation

@MainActor @Observable
final class BudgetViewModel {
    var month = Date()
    var transactions: [BudgetTransaction] = []
    var categories: [BudgetCategory] = []

    func load() {
        BudgetStore.populateRecurring()
        categories = BudgetStore.categories()
        transactions = BudgetStore.transactions(in: month)
    }

    func shift(_ months: Int) {
        month = Calendar.current.date(byAdding: .month, value: months, to: month)!
        load()
    }

    var spent: [String: Double] { transactions.reduce(into: [:]) { $0[$1.category, default: 0] += $1.amount } }
    var totalSpent: Double { transactions.filter { $0.amount > 0 }.map(\.amount).reduce(0, +) }
    var totalBudget: Double { categories.map(\.monthlyBudget).reduce(0, +) }

    struct Row: Identifiable { let id: String; let category: String; let kind: String; let amount: Double }
    var barRows: [Row] {
        let s = spent
        let names = Array(Set(categories.map(\.name) + s.keys.filter { (s[$0] ?? 0) > 0 })).sorted()
        return names.flatMap { n in
            [Row(id: n + "b", category: n, kind: "Budget", amount: categories.first { $0.name == n }?.monthlyBudget ?? 0),
             Row(id: n + "a", category: n, kind: "Actual", amount: max(0, s[n] ?? 0))]
        }
    }

    func color(_ category: String) -> String { categories.first { $0.name == category }?.color ?? "gray" }
}
