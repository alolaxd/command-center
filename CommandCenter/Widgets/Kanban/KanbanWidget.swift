import SwiftUI

struct KanbanWidget: DashboardWidget {
    static let kind = "kanban"
    static let title = "Kanban"
    static let symbol = "rectangle.split.3x1"
    static let summary = "Backlog → Done board with drag & drop, WIP limits, swimlanes and links to reminders, notes and repos."
    static let category = WidgetCategory.productivity
    static let minSize = GridSize(4, 3)
    static let defaultSize = GridSize(8, 4)

    let context: WidgetContext<KanbanConfiguration>
    @State private var vm = KanbanViewModel()
    @State private var editing: KanbanCard?

    init(context: WidgetContext<KanbanConfiguration>) { self.context = context }

    private var columns: [KanbanColumn] { KanbanColumn.allCases.filter { !context.config.hiddenColumns.contains($0.rawValue) } }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 10) {
                if context.config.swimlanes == .lane {
                    ForEach(vm.lanes, id: \.self) { lane in
                        Text(lane.isEmpty ? "No project" : "#" + lane).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        board(lane: lane)
                    }
                    if vm.lanes.isEmpty { board(lane: "") }
                } else {
                    board(lane: nil)
                }
            }
        }
        .onAppear { vm.load() }
        .onReceive(WidgetBus.shared.events) { e in
            switch e {
            case .dataChanged("kanban"): vm.load()
            case .createKanbanCard(let title): KanbanStore.addCard(title: title); vm.load()
            default: break
            }
        }
        .sheet(item: $editing) { card in KanbanCardEditor(card: card) { vm.load() } }
    }

    private func board(lane: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(columns) { col in column(col, lane: lane) }
        }
    }

    private func column(_ col: KanbanColumn, lane: String?) -> some View {
        let items = vm.cards(col, lane: lane)
        let over = vm.isOverLimit(col, context.config)
        let limit = context.config.wipLimits[col.rawValue]
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(col.rawValue).font(.caption.weight(.semibold))
                Spacer()
                Text(limit.map { "\(items.count)/\($0)" } ?? "\(items.count)").font(.caption2.monospacedDigit())
                    .foregroundStyle(over ? .red : .secondary)
            }
            ForEach(items) { card in
                cardView(card)
                    .draggable(card.id)
                    .dropDestination(for: String.self) { ids, _ in vm.drop(ids, on: col, lane: lane, before: card.id); return true }
            }
            if col == .backlog || col == .todo {
                AddField(prompt: "Add card") { vm.add($0, column: col, lane: lane ?? "") }
            }
            Spacer(minLength: 20)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background((over ? Color.red.opacity(0.12) : Color.primary.opacity(0.04)), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(over ? Color.red.opacity(0.7) : .clear))
        .dropDestination(for: String.self) { ids, _ in vm.drop(ids, on: col, lane: lane); return true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(col.rawValue), \(items.count) cards\(over ? ", over WIP limit" : "")")
    }

    private func cardView(_ card: KanbanCard) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(card.title).font(.callout).lineLimit(3)
            HStack(spacing: 4) {
                if let link = card.link { Image(systemName: link.symbol).font(.caption2).foregroundStyle(.secondary) }
                if !card.lane.isEmpty { Text("#" + card.lane).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.08)))
        .onTapGesture(count: 2) { editing = card }
        .contextMenu {
            Menu("Move to") {
                ForEach(KanbanColumn.allCases) { c in Button(c.rawValue) { vm.drop([card.id], on: c, lane: nil) } }
            }
            Button("Edit…") { editing = card }
            Button("Start Pomodoro") { PomodoroEngine.shared.start(task: card.title) }
            if let link = card.link { Button("Open Link") { KanbanLinkOpener.open(link) } }
            Divider()
            Button("Delete", role: .destructive) { KanbanStore.delete(card.id); vm.load() }
        }
        .accessibilityLabel(card.title)
    }
}

enum KanbanLinkOpener {
    @MainActor static func open(_ link: KanbanLink) {
        switch link {
        case .url(let s): if let u = URL(string: s) { NSWorkspace.shared.open(u) }
        case .repo(let path): NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: (path as NSString).expandingTildeInPath)])
        case .note(let title): _ = WorkspaceStore.shared.focusFirst(kind: "notes"); WidgetBus.shared.toast("Open note: \(title)", symbol: "note.text")
        case .reminder: NSWorkspace.shared.open(URL(string: "x-apple-reminderkit://")!)
        }
    }
}

struct KanbanCardEditor: View {
    @State var card: KanbanCard
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var linkType = "none"
    @State private var linkValue = ""

    var body: some View {
        Form {
            TextField("Title", text: $card.title)
            TextField("Project / tag (swimlane)", text: $card.lane)
            Picker("Column", selection: $card.column) { ForEach(KanbanColumn.allCases) { Text($0.rawValue).tag($0) } }
            TextField("Details", text: $card.details, axis: .vertical).lineLimit(3...6)
            Picker("Link", selection: $linkType) {
                Text("None").tag("none"); Text("Reminder").tag("reminder"); Text("Note").tag("note"); Text("Git repo").tag("repo"); Text("URL").tag("url")
            }
            if linkType != "none" {
                TextField(linkType == "repo" ? "~/Projects/app" : linkType == "note" ? "Note title" : "Value", text: $linkValue)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    card.link = KanbanLink(type: linkType, value: linkValue)
                    KanbanStore.save(card); onSave(); dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 380)
        .onAppear { linkType = card.linkType ?? "none"; linkValue = card.linkValue ?? "" }
    }
}
