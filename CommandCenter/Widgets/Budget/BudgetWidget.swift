import Charts
import SwiftUI

struct BudgetWidget: DashboardWidget {
    static let kind = "budget"
    static let title = "Budget"
    static let symbol = "creditcard"
    static let summary = "Quick transaction entry, monthly budget vs actual, category breakdown and recurring expenses."
    static let category = WidgetCategory.finance
    static let defaultSize = GridSize(4, 4)

    let context: WidgetContext<BudgetConfiguration>
    @State private var vm = BudgetViewModel()
    @State private var view: BudgetConfiguration.Mode?

    init(context: WidgetContext<BudgetConfiguration>) { self.context = context }

    var body: some View {
        let mode = view ?? context.config.view
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { vm.shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).accessibilityLabel("Previous month")
                Text(vm.month.formatted(.dateTime.month(.wide).year())).font(.callout.weight(.semibold))
                Button { vm.shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless).accessibilityLabel("Next month")
                Spacer()
                StatTile(label: "Spent", value: vm.totalSpent.currency, detail: "of \(vm.totalBudget.currency)",
                         tint: vm.totalSpent > vm.totalBudget ? .red : .primary).fixedSize()
            }
            AddField(prompt: "12.50 lunch dining   ·   -2000 salary") { text in
                if BudgetStore.quickAdd(text) == nil { WidgetBus.shared.toast("Start with an amount, e.g. “12.50 coffee dining”") }
                vm.load()
            }
            Picker("", selection: Binding(get: { mode }, set: { view = $0 })) {
                ForEach(BudgetConfiguration.Mode.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented).labelsHidden()
            switch mode {
            case .bars:
                Chart(vm.barRows) { r in
                    BarMark(x: .value("Category", r.category), y: .value("Amount", r.amount))
                        .foregroundStyle(by: .value("Kind", r.kind))
                        .position(by: .value("Kind", r.kind))
                }
                .chartForegroundStyleScale(["Budget": Color.secondary.opacity(0.35), "Actual": Color.accentColor])
                .chartLegend(position: .top, alignment: .trailing)
                .accessibilityLabel("Budget versus actual by category")
            case .donut:
                let entries = vm.spent.filter { $0.value > 0 }.sorted { $0.value > $1.value }
                HStack {
                    Chart(entries, id: \.key) { e in
                        SectorMark(angle: .value("Spent", e.value), innerRadius: .ratio(0.6), angularInset: 1)
                            .foregroundStyle(Palette.color(vm.color(e.key)))
                    }
                    .chartLegend(.hidden)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(entries, id: \.key) { e in
                            HStack {
                                Circle().fill(Palette.color(vm.color(e.key))).frame(width: 8, height: 8)
                                Text(e.key).font(.caption)
                                Spacer()
                                Text(e.value.currency).font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: 170)
                }
                .overlay { if entries.isEmpty { Text("No expenses this month").font(.caption).foregroundStyle(.secondary) } }
            case .list:
                List(vm.transactions) { t in
                    HStack {
                        Circle().fill(Palette.color(vm.color(t.category))).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(t.note.isEmpty ? t.category : t.note).font(.callout).lineLimit(1)
                            Text("\(t.category) · \(t.date.formatted(date: .abbreviated, time: .omitted))").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(t.amount < 0 ? "+" + (-t.amount).currency : t.amount.currency)
                            .font(.callout.monospacedDigit()).foregroundStyle(t.amount < 0 ? .green : .primary)
                    }
                    .contextMenu { Button("Delete", role: .destructive) { BudgetStore.delete(t); vm.load() } }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .onAppear { vm.load() }
    }
}
