import EventKit
import SwiftUI

struct RemindersWidget: DashboardWidget {
    static let kind = "reminders"
    static let title = "Reminders"
    static let symbol = "checklist"
    static let summary = "Today, overdue and upcoming Apple Reminders with natural-language add."
    static let category = WidgetCategory.productivity
    static let defaultSize = GridSize(3, 4)
    static let refreshInterval: TimeInterval? = 60

    let context: WidgetContext<RemindersConfiguration>
    @State private var vm = RemindersViewModel()
    private var ek: EventKitService { .shared }

    init(context: WidgetContext<RemindersConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !ek.remindersAuthorized {
                PermissionPrompt(symbol: "checklist", title: "Reminders access needed",
                                 message: "Allow access to show and edit your Apple Reminders.", buttonTitle: "Allow Access") {
                    Task { await ek.requestReminders(); await vm.load(context.config) }
                }
            } else {
                AddField(prompt: "Buy milk tomorrow 3pm") { text in
                    RemindersStore.add(text, listID: context.config.listIDs.first)
                    Task { await vm.load(context.config) }
                }
                List {
                    section("Overdue", vm.overdue, tint: .red)
                    section("Today", vm.today, tint: .accentColor)
                    section("Next \(context.config.upcomingHours)h", vm.upcoming, tint: .secondary)
                    section("No Date", vm.undated, tint: .secondary)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if vm.overdue.isEmpty && vm.today.isEmpty && vm.upcoming.isEmpty && vm.undated.isEmpty && !vm.loading {
                        EmptyStateView(symbol: "checkmark.circle", title: "All clear")
                    }
                }
            }
        }
        .refreshing(every: Self.refreshInterval) { await vm.load(context.config) }
        .onChange(of: ek.changeToken) { Task { await vm.load(context.config) } }
        .onChange(of: context.config) { Task { await vm.load(context.config) } }
    }

    @ViewBuilder
    private func section(_ title: String, _ items: [EKReminder], tint: Color) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.calendarItemIdentifier) { r in row(r, tint: tint) }
                    .onMove { vm.move(in: items, from: $0, to: $1, config: context.config) }
            } header: {
                Text("\(title) · \(items.count)").font(.caption.weight(.semibold)).foregroundStyle(tint)
            }
        }
    }

    private func row(_ r: EKReminder, tint: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button { RemindersStore.complete(r); Task { await vm.load(context.config) } } label: {
                Image(systemName: "circle").foregroundStyle(Color(cgColor: r.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1)))
            }
            .buttonStyle(.plain).accessibilityLabel("Complete \(r.title ?? "")")
            VStack(alignment: .leading, spacing: 1) {
                Text(r.title ?? "").font(.callout).lineLimit(2)
                if let due = r.dueDate {
                    Text(due.formatted(r.dueDateComponents?.hour != nil ? .dateTime.weekday().hour().minute() : .dateTime.weekday().month().day()))
                        .font(.caption2).foregroundStyle(tint == .red ? .red : .secondary)
                }
            }
            Spacer()
            if r.priority > 0 && r.priority <= 4 { Image(systemName: "exclamationmark").font(.caption).foregroundStyle(.orange) }
        }
        .contextMenu {
            Button("Snooze 1 Hour") { RemindersStore.snooze(r, by: 3600); reload() }
            Button("Snooze Until Tomorrow") { RemindersStore.snooze(r, by: 86400); reload() }
            Button("Snooze 1 Week") { RemindersStore.snooze(r, by: 7 * 86400); reload() }
            Divider()
            Button("Send to Kanban") { KanbanStore.addCard(title: r.title ?? "", link: .reminder(r.calendarItemIdentifier)) }
            Button("Start Pomodoro on This") { PomodoroEngine.shared.start(task: r.title) }
            Divider()
            Button("Delete", role: .destructive) { RemindersStore.delete(r); reload() }
        }
        .accessibilityElement(children: .combine)
    }

    private func reload() { Task { await vm.load(context.config) } }
}
