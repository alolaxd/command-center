import SwiftUI

struct HealthWidget: DashboardWidget {
    static let kind = "health"
    static let title = "Health"
    static let symbol = "heart.text.square"
    static let summary = "Move / Exercise / Stand rings, steps, heart rate, sleep, weekly trends and a water tracker."
    static let category = WidgetCategory.lifestyle
    static let defaultSize = GridSize(4, 4)

    let context: WidgetContext<HealthConfiguration>
    @State private var vm = HealthViewModel()
    @State private var logMetric: HealthMetric = .steps
    @State private var logValue = ""

    init(context: WidgetContext<HealthConfiguration>) { self.context = context }

    var body: some View {
        let t = vm.today
        let c = context.config
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    ZStack {
                        ProgressRing(fraction: (t[.activeCalories] ?? 0) / c.moveGoal, tint: .red, lineWidth: 8).frame(width: 84, height: 84)
                        ProgressRing(fraction: (t[.exerciseMinutes] ?? 0) / c.exerciseGoal, tint: .green, lineWidth: 8).frame(width: 64, height: 64)
                        ProgressRing(fraction: (t[.standHours] ?? 0) / c.standGoal, tint: .cyan, lineWidth: 8).frame(width: 44, height: 44)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Rings: move \(Int(t[.activeCalories] ?? 0)) of \(Int(c.moveGoal)) kilocalories, exercise \(Int(t[.exerciseMinutes] ?? 0)) of \(Int(c.exerciseGoal)) minutes, stand \(Int(t[.standHours] ?? 0)) of \(Int(c.standGoal)) hours")
                    VStack(alignment: .leading, spacing: 3) {
                        ring("Move", t[.activeCalories], c.moveGoal, "kcal", .red)
                        ring("Exercise", t[.exerciseMinutes], c.exerciseGoal, "min", .green)
                        ring("Stand", t[.standHours], c.standGoal, "h", .cyan)
                    }
                }
                HStack {
                    trend("Steps", t[.steps], .steps, .orange)
                    trend("Heart", t[.heartRate], .heartRate, .pink, unit: " bpm")
                    trend("Sleep", t[.sleepHours], .sleepHours, .indigo, unit: " h", decimals: 1)
                }
                HStack {
                    Image(systemName: "drop.fill").foregroundStyle(.blue)
                    MeterBar(fraction: (t[.water] ?? 0) / c.waterGoal, tint: .blue)
                    Text("\(Int(t[.water] ?? 0)) / \(Int(c.waterGoal)) ml").font(.caption.monospacedDigit())
                    Button("+\(Int(c.waterIncrement))") { HealthStore.add(.water, c.waterIncrement); vm.load() }.controlSize(.small)
                }
                HStack {
                    Picker("", selection: $logMetric) {
                        ForEach([HealthMetric.steps, .activeCalories, .exerciseMinutes, .standHours, .sleepHours, .heartRate, .workouts], id: \.self) { Text($0.label) }
                    }
                    .labelsHidden().frame(width: 140)
                    TextField("Amount", text: $logValue).textFieldStyle(.roundedBorder).frame(width: 70).onSubmit(log)
                    Button("Log", action: log).controlSize(.small)
                    Spacer()
                    Button(vm.importing ? "Importing…" : "Import Health Export…") { Task { await vm.importExport() } }
                        .controlSize(.small).disabled(vm.importing)
                }
                Text("Mac apps can't read Apple Health directly; log here or import an export from your iPhone.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onAppear { vm.load(); vm.checkStepGoal(c.stepGoal) }
    }

    private func log() {
        guard let v = Double(logValue) else { return }
        if logMetric == .heartRate { HealthStore.set(.heartRate, v, day: Date().dayKey, source: "manual") } else { HealthStore.add(logMetric, v) }
        logValue = ""
        vm.load()
        vm.checkStepGoal(context.config.stepGoal)
    }

    private func ring(_ label: String, _ value: Double?, _ goal: Double, _ unit: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption).frame(width: 56, alignment: .leading)
            Text("\(Int(value ?? 0))/\(Int(goal)) \(unit)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func trend(_ label: String, _ value: Double?, _ m: HealthMetric, _ color: Color, unit: String = "", decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            StatTile(label: label, value: value.map { $0.formatted(.number.precision(.fractionLength(decimals))) + unit } ?? "—")
            Sparkline(values: vm.week(m), color: color, lineWidth: 1.2).frame(height: 16)
        }
    }
}
