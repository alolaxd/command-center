import SwiftUI

struct PomodoroWidget: DashboardWidget {
    static let kind = "pomodoro"
    static let title = "Pomodoro"
    static let symbol = "timer"
    static let summary = "25/5 focus timer with circular countdown, task linking, habit logging and optional app blocking."
    static let category = WidgetCategory.productivity
    static let defaultSize = GridSize(2, 3)

    let context: WidgetContext<PomodoroConfiguration>
    @State private var todayCount = PomodoroStore.countToday()
    @State private var cards: [KanbanCard] = []
    private var engine: PomodoroEngine { .shared }

    init(context: WidgetContext<PomodoroConfiguration>) { self.context = context }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ProgressRing(fraction: engine.fraction, tint: engine.phase == .focus || engine.phase == .idle ? .red : .green, lineWidth: 7)
                VStack(spacing: 0) {
                    Text(timeString(engine.remaining)).font(.title.monospacedDigit().weight(.semibold))
                    Text(engine.phase.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: 150, maxHeight: 150)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(engine.phase.rawValue), \(timeString(engine.remaining)) remaining")

            Menu {
                Button("No task") { engine.task = nil }
                ForEach(cards.prefix(15)) { c in Button(c.title) { engine.task = c.title } }
            } label: {
                Label(engine.task ?? "Choose task…", systemImage: "scope").lineLimit(1).font(.caption)
            }
            .menuStyle(.borderlessButton).fixedSize()

            HStack {
                Button { engine.isRunning ? engine.pause() : engine.start() } label: {
                    Image(systemName: engine.isRunning ? "pause.fill" : "play.fill").frame(width: 20)
                }
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityLabel(engine.isRunning ? "Pause" : "Start")
                Button { engine.skip() } label: { Image(systemName: "forward.end.fill") }.accessibilityLabel("Skip")
                Button { engine.reset() } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("Reset")
            }
            .controlSize(.small)
            Text("\(todayCount) today").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            engine.apply(context.config)
            cards = KanbanStore.all().filter { $0.column == .inProgress || $0.column == .todo }
        }
        .onChange(of: context.config) { engine.apply(context.config) }
        .onReceive(WidgetBus.shared.events) { e in if case .pomodoroCompleted = e { todayCount = PomodoroStore.countToday() } }
    }

    private func timeString(_ t: TimeInterval) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }
}
