import Foundation

@MainActor @Observable
final class JournalViewModel {
    var day = Calendar.current.startOfDay(for: Date())
    var entry = JournalEntry(day: Date().dayKey)
    var summary: String?
    var summarizing = false
    var daysWithEntries: Set<String> = []
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    func load() {
        entry = JournalStore.entry(day)
        daysWithEntries = JournalStore.daysWithEntries()
        summary = JournalStore.summary(weekStart: JournalStore.weekStart(day))?.text
    }

    func shift(_ days: Int) {
        flush()
        day = Calendar.current.date(byAdding: .day, value: days, to: day)!
        load()
    }

    func changed() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() { JournalStore.save(entry); daysWithEntries = JournalStore.daysWithEntries() }

    func summarize() async {
        summarizing = true
        defer { summarizing = false }
        do { summary = try await JournalStore.generateSummary(weekStart: JournalStore.weekStart(day)) }
        catch { summary = "⚠️ \(error.localizedDescription)" }
    }

    /// End-of-week: once the week is over, summarize it automatically (if AI is configured).
    func autoSummarizeLastWeek() async {
        guard AIService.shared.isConfigured else { return }
        let lastWeek = JournalStore.weekStart(Date().addingTimeInterval(-7 * 86400))
        guard JournalStore.summary(weekStart: lastWeek) == nil,
              !JournalStore.entries(from: lastWeek, to: lastWeek.addingTimeInterval(6 * 86400)).isEmpty else { return }
        _ = try? await JournalStore.generateSummary(weekStart: lastWeek)
        WidgetBus.shared.toast("Your weekly journal summary is ready", symbol: "book")
    }
}
