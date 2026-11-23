import SwiftUI

struct HabitTrackerWidget: DashboardWidget {
    static let kind = "habits"
    static let title = "Habit Tracker"
    static let symbol = "square.grid.3x3.fill"
    static let summary = "Daily/weekly habits on a contribution grid with streaks and auto-completion from other widgets."
    static let category = WidgetCategory.productivity
    static let defaultSize = GridSize(4, 3)

    let context: WidgetContext<HabitTrackerConfiguration>
    @State private var vm = HabitTrackerViewModel()
    @State private var editing: Habit?

    init(context: WidgetContext<HabitTrackerConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(vm.habits) { h in habitRow(h) }
                }
            }
            AddField(prompt: "New habit") { vm.add($0, weeks: context.config.weeks) }
        }
        .onAppear { vm.load(weeks: context.config.weeks) }
        .onChange(of: context.config) { vm.load(weeks: context.config.weeks) }
        .onReceive(WidgetBus.shared.events) { e in if case .dataChanged("habits") = e { vm.load(weeks: context.config.weeks) } }
        .sheet(item: $editing) { h in HabitEditor(habit: h) { vm.load(weeks: context.config.weeks) } }
    }

    private func habitRow(_ h: Habit) -> some View {
        let color = Palette.color(h.color)
        let (cur, best) = vm.streaks[h.id] ?? (0, 0)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button { HabitStore.toggle(h.id); vm.load(weeks: context.config.weeks) } label: {
                    Image(systemName: vm.done(h, Date()) ? "checkmark.circle.fill" : "circle").foregroundStyle(color)
                }
                .buttonStyle(.plain).accessibilityLabel("Toggle \(h.name) today")
                Image(systemName: h.symbol).foregroundStyle(color).font(.caption)
                Text(h.name).font(.callout.weight(.medium))
                if h.weeklyTarget < 7 { Text("\(vm.weekCount(h))/\(h.weeklyTarget) this week").font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Label("\(cur)", systemImage: "flame").font(.caption.monospacedDigit()).foregroundStyle(cur > 0 ? .orange : .secondary)
                Text("best \(best)").font(.caption2).foregroundStyle(.secondary)
            }
            .contextMenu {
                Button("Edit…") { editing = h }
                Button("Archive", role: .destructive) { var x = h; x.archived = true; HabitStore.save(x); vm.load(weeks: context.config.weeks) }
            }
            if context.config.style == .grid {
                HStack(alignment: .top, spacing: 2) {
                    ForEach(vm.gridWeeks(context.config.weeks), id: \.first) { week in
                        VStack(spacing: 2) {
                            ForEach(week, id: \.self) { day in
                                let future = day > Date()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(future ? Color.clear : vm.done(h, day) ? color : Color.primary.opacity(0.08))
                                    .frame(width: 9, height: 9)
                                    .onTapGesture { if !future { HabitStore.toggle(h.id, day: day); vm.load(weeks: context.config.weeks) } }
                                    .help(day.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }
                }
                .accessibilityHidden(true)
            } else {
                HStack(spacing: 4) {
                    ForEach(vm.gridWeeks(1)[0], id: \.self) { day in
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                            Circle().fill(vm.done(h, day) ? color : Color.primary.opacity(0.08)).frame(width: 16, height: 16)
                                .onTapGesture { HabitStore.toggle(h.id, day: day); vm.load(weeks: context.config.weeks) }
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(h.name), current streak \(cur) days, best \(best)")
    }
}

struct HabitEditor: View {
    @State var habit: Habit
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            TextField("Name", text: $habit.name)
            TextField("SF Symbol", text: $habit.symbol)
            LabeledContent("Color") { PalettePicker(selection: $habit.color) }
            Stepper("Target: \(habit.weeklyTarget)× per week", value: $habit.weeklyTarget, in: 1...7)
            Picker("Auto-complete from", selection: Binding(get: { habit.autoSource ?? "" }, set: { habit.autoSource = $0.isEmpty ? nil : $0 })) {
                Text("Manual only").tag("")
                Text("Pomodoro sessions").tag("pomodoro")
                Text("Health: workouts").tag("health.workout")
                Text("Health: step goal").tag("health.steps")
                Text("Journal entry").tag("journal")
            }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { HabitStore.save(habit); onSave(); dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding().frame(width: 360)
    }
}
