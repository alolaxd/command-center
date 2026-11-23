import SwiftUI

struct CountdownWidget: DashboardWidget {
    static let kind = "countdowns"
    static let title = "Countdowns"
    static let symbol = "hourglass"
    static let summary = "Named countdowns with progress bars and milestone notifications (1 week, 1 day, 1 hour)."
    static let category = WidgetCategory.utility
    static let defaultSize = GridSize(3, 3)
    static let refreshInterval: TimeInterval? = 30

    let context: WidgetContext<CountdownConfiguration>
    @State private var vm = CountdownViewModel()
    @State private var editing: Countdown?

    init(context: WidgetContext<CountdownConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AddField(prompt: "Vacation on Jan 15 · Launch in 12 days") { text in
                if !vm.add(text, config: context.config) { WidgetBus.shared.toast("Include a future date, e.g. “Launch in 12 days”") }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(vm.items) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: c.symbol).foregroundStyle(Palette.color(c.color))
                                Text(c.name).font(.callout.weight(.medium)).lineLimit(1)
                                Spacer()
                                Text(CountdownStore.format(c.remaining)).font(.callout.monospacedDigit().weight(.semibold))
                            }
                            MeterBar(fraction: c.progress, tint: Palette.color(c.color))
                            Text(c.target.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { editing = c }
                        .contextMenu {
                            Button("Edit…") { editing = c }
                            Button("Delete", role: .destructive) { CountdownStore.delete(c); vm.load(context.config) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .overlay { if vm.items.isEmpty { EmptyStateView(symbol: "hourglass", title: "No countdowns") } }
        }
        .refreshing(every: Self.refreshInterval) { vm.load(context.config) }
        .sheet(item: $editing) { c in CountdownEditor(countdown: c) { vm.load(context.config) } }
    }
}

struct CountdownEditor: View {
    @State var countdown: Countdown
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Name", text: $countdown.name)
            DatePicker("Target", selection: $countdown.target)
            DatePicker("Counting from", selection: $countdown.start)
            TextField("SF Symbol", text: $countdown.symbol)
            LabeledContent("Color") { PalettePicker(selection: $countdown.color) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { CountdownStore.save(countdown); onSave(); dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding().frame(width: 380)
    }
}
