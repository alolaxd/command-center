import SwiftUI

struct BudgetConfiguration: WidgetConfiguration {
    enum Mode: String, Codable, CaseIterable { case bars = "Budget vs Actual", donut = "Breakdown", list = "Transactions" }
    var view: Mode = .bars

    static func editor(_ config: Binding<Self>) -> some View { BudgetSettings(config: config) }
}

private struct BudgetSettings: View {
    @Binding var config: BudgetConfiguration
    @State private var categories = BudgetStore.categories()
    @State private var recurring = BudgetStore.recurring()
    @State private var newCat = ""
    var body: some View {
        Form {
            Picker("Default view", selection: $config.view) { ForEach(BudgetConfiguration.Mode.allCases, id: \.self) { Text($0.rawValue) } }
            Section("Monthly budgets") {
                ForEach($categories) { $c in
                    HStack {
                        PalettePicker(selection: $c.color).scaleEffect(0.8)
                        Text(c.name)
                        Spacer()
                        TextField("Budget", value: $c.monthlyBudget, format: .number).frame(width: 80)
                            .onSubmit { BudgetStore.save(c) }
                    }
                    .onChange(of: c) { BudgetStore.save(c) }
                }
                HStack {
                    TextField("New category", text: $newCat)
                    Button("Add") { BudgetStore.save(BudgetCategory(name: newCat, monthlyBudget: 100)); newCat = ""; categories = BudgetStore.categories() }
                        .disabled(newCat.isEmpty)
                }
            }
            Section("Recurring expenses") {
                ForEach($recurring) { $r in
                    HStack {
                        TextField("Note", text: $r.note)
                        TextField("Amount", value: $r.amount, format: .number).frame(width: 70)
                        Picker("", selection: $r.category) { ForEach(categories) { Text($0.name).tag($0.name) } }.labelsHidden().frame(width: 110)
                        Stepper("day \(r.dayOfMonth)", value: $r.dayOfMonth, in: 1...31).fixedSize()
                        Button { BudgetStore.delete(r); recurring = BudgetStore.recurring() } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless)
                    }
                    .onChange(of: r) { BudgetStore.save(r) }
                }
                Button("Add Recurring Expense") {
                    BudgetStore.save(RecurringExpense(amount: 10, category: categories.first?.name ?? "Other", dayOfMonth: 1, note: "Subscription"))
                    recurring = BudgetStore.recurring()
                }
            }
        }
    }
}
