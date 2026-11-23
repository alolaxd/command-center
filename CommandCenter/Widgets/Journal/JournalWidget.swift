import SwiftUI

struct JournalWidget: DashboardWidget {
    static let kind = "journal"
    static let title = "Daily Journal"
    static let symbol = "book"
    static let summary = "One Markdown entry per day with mood, reflection prompts and an AI weekly summary."
    static let category = WidgetCategory.productivity
    static let defaultSize = GridSize(4, 4)

    let context: WidgetContext<JournalConfiguration>
    @State private var vm = JournalViewModel()
    @State private var showSummary = false

    init(context: WidgetContext<JournalConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { vm.shift(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless).accessibilityLabel("Previous day")
                Text(vm.day.formatted(.dateTime.weekday(.wide).month().day())).font(.callout.weight(.semibold))
                Button { vm.shift(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                    .disabled(Calendar.current.isDateInToday(vm.day)).accessibilityLabel("Next day")
                Spacer()
                weekDots
                Button { showSummary = true; if vm.summary == nil { Task { await vm.summarize() } } } label: { Image(systemName: "sparkles") }
                    .buttonStyle(.borderless).help("Weekly AI summary").accessibilityLabel("Weekly summary")
            }
            HStack(spacing: 6) {
                Text("Mood").font(.caption).foregroundStyle(.secondary)
                ForEach(1...5, id: \.self) { m in
                    Button { vm.entry.mood = vm.entry.mood == m ? 0 : m; vm.changed() } label: {
                        Text(JournalEntry.moods[m]).font(.title3).opacity(vm.entry.mood == 0 || vm.entry.mood == m ? 1 : 0.3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Mood \(m) of 5").accessibilityAddTraits(vm.entry.mood == m ? .isSelected : [])
                }
            }
            TextEditor(text: Binding(get: { vm.entry.body }, set: { vm.entry.body = $0; vm.changed() }))
                .font(.callout).scrollContentBackground(.hidden)
                .padding(4).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                .frame(minHeight: 60)
                .accessibilityLabel("Journal entry")
            if context.config.showPrompts {
                prompt("What went well?", \.wentWell)
                prompt("What could improve?", \.improve)
                prompt("Grateful for?", \.grateful)
            }
        }
        .onAppear { vm.load() ; if context.config.autoWeeklySummary { Task { await vm.autoSummarizeLastWeek() } } }
        .onDisappear { vm.flush() }
        .sheet(isPresented: $showSummary) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Week of \(JournalStore.weekStart(vm.day).formatted(date: .abbreviated, time: .omitted))").font(.headline)
                    Spacer()
                    Button("Regenerate") { Task { await vm.summarize() } }.disabled(vm.summarizing)
                    Button("Done") { showSummary = false }.keyboardShortcut(.defaultAction)
                }
                ScrollView { if vm.summarizing { ProgressView() } else { MarkdownView(text: vm.summary ?? "") } }
            }
            .padding().frame(width: 480, height: 420)
        }
    }

    private func prompt(_ label: String, _ key: WritableKeyPath<JournalEntry, String>) -> some View {
        TextField(label, text: Binding(get: { vm.entry[keyPath: key] }, set: { vm.entry[keyPath: key] = $0; vm.changed() }), axis: .vertical)
            .textFieldStyle(.plain).font(.callout).lineLimit(1...3)
            .padding(4).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }

    private var weekDots: some View {
        let start = JournalStore.weekStart(vm.day)
        return HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: start)!
                Circle().fill(vm.daysWithEntries.contains(d.dayKey) ? Color.accentColor : Color.primary.opacity(0.12))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}
