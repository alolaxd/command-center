import Foundation

/// Builds a compact snapshot of the user's local data so the AI can answer
/// "ask about my data" questions (pomodoros, commits, expenses, habits, agents...).
@MainActor
enum AIDataContext {
    static func snapshot() async -> String {
        var sections: [String] = ["Today is \(Date().formatted(date: .complete, time: .shortened))."]
        sections.append(PomodoroStore.aiSummary())
        sections.append(HabitStore.aiSummary())
        sections.append(BudgetStore.aiSummary())
        sections.append(JournalStore.aiSummary())
        sections.append(KanbanStore.aiSummary())
        sections.append(InboxStore.aiSummary())
        sections.append(AgentMonitorStore.aiSummary())
        sections.append(ScreenTimeStore.aiSummary())
        sections.append(await GitDashboardStore.aiSummary())
        sections.append(await RemindersStore.aiSummary())
        sections.append(await CalendarStore.aiSummary())
        return sections.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static let systemPrompt = """
    You are the assistant inside Command Center, a personal macOS dashboard. \
    You are given a snapshot of the user's local data (pomodoros, habits, budget, journal, kanban, inbox, \
    git activity, reminders, calendar, AI agent usage). Answer questions about it concisely and precisely, \
    citing numbers from the snapshot. If the snapshot lacks the data, say what is missing.
    """
}
