import SwiftUI

struct GitDashboardWidget: DashboardWidget {
    static let kind = "git"
    static let title = "Git Dashboard"
    static let symbol = "arrow.triangle.branch"
    static let summary = "Branch, changes, ahead/behind, recent commits, quick actions, PR status and a commit heatmap for your repos."
    static let category = WidgetCategory.aiDev
    static let minSize = GridSize(3, 3)
    static let defaultSize = GridSize(5, 4)
    static let refreshInterval: TimeInterval? = 60

    let context: WidgetContext<GitDashboardConfiguration>
    @State private var vm = GitDashboardViewModel()
    @State private var expanded: Set<String> = []

    init(context: WidgetContext<GitDashboardConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if context.config.repos.isEmpty {
                EmptyStateView(symbol: "folder.badge.plus", title: "No repositories", message: "Pick the folders to monitor.",
                               action: ("Add Repositories…", addRepos))
            } else {
                if context.config.showHeatmap { heatmap }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.repos) { repo in repoCard(repo) }
                    }
                }
                if let out = vm.lastOutput {
                    Text(out).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                        .onTapGesture { vm.lastOutput = nil }
                }
            }
        }
        .refreshing(every: Self.refreshInterval) { await vm.load(context.config) }
        .task(id: context.config.repos) { await vm.loadHeatmap(context.config) }
        .onChange(of: context.config) { Task { await vm.load(context.config) } }
    }

    private func addRepos() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        guard p.runModal() == .OK else { return }
        var c = context.config
        c.repos.append(contentsOf: p.urls.map(\.path))
        context.updateConfig(c)
    }

    private func repoCard(_ r: GitRepoStatus) -> some View {
        let isOpen = expanded.contains(r.path)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button { if isOpen { expanded.remove(r.path) } else { expanded.insert(r.path) } } label: {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right").font(.caption)
                }.buttonStyle(.borderless).accessibilityLabel(isOpen ? "Collapse" : "Expand")
                Text(r.name).font(.callout.weight(.semibold))
                Menu {
                    ForEach(r.branches, id: \.self) { b in
                        Button(b) { Task { await vm.switchBranch(b, r, config: context.config) } }.disabled(b == r.branch)
                    }
                } label: { Label(r.branch, systemImage: "arrow.triangle.branch").font(.caption) }
                    .menuStyle(.borderlessButton).fixedSize().help("Switch branch")
                if r.ahead > 0 { Text("↑\(r.ahead)").font(.caption.monospacedDigit()).foregroundStyle(.green) }
                if r.behind > 0 { Text("↓\(r.behind)").font(.caption.monospacedDigit()).foregroundStyle(.orange) }
                Spacer()
                if vm.busy.contains(r.path) { ProgressView().controlSize(.small) }
                if r.isClean { Image(systemName: "checkmark.circle").foregroundStyle(.green).font(.caption).accessibilityLabel("Clean") }
                else {
                    Text(changes(r)).font(.caption.monospacedDigit()).foregroundStyle(r.conflicts > 0 ? .red : .orange)
                }
                Menu {
                    Button("Fetch") { Task { await vm.run(.fetch, r, config: context.config) } }
                    Button("Pull (fast-forward)") { Task { await vm.run(.pull, r, config: context.config) } }
                    Button("Push") { Task { await vm.run(.push, r, config: context.config) } }
                    Divider()
                    Button("Stash Changes") { Task { await vm.run(.stash, r, config: context.config) } }
                    Button("Pop Stash") { Task { await vm.run(.stashPop, r, config: context.config) } }
                    Divider()
                    Button("Open in Terminal Pane") { WidgetBus.shared.publish(.runInTerminal("cd '\(r.path)'")) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: r.path)]) }
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Git actions")
            }
            if let e = r.error { Text(e).font(.caption).foregroundStyle(.red).lineLimit(2) }
            if isOpen {
                ForEach(r.commits) { c in
                    HStack(spacing: 6) {
                        Text(c.hash).font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(c.subject).font(.caption).lineLimit(1)
                        Spacer()
                        Text(c.date.formatted(.relative(presentation: .numeric))).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            if context.config.showPRs, let prs = vm.prs[r.path], !prs.isEmpty {
                ForEach(prs.prefix(isOpen ? 10 : 2)) { pr in
                    HStack(spacing: 6) {
                        Image(systemName: pr.draft ? "circle.dashed" : "arrow.triangle.pull").font(.caption)
                            .foregroundStyle(pr.branch == r.branch ? Color.accentColor : .secondary)
                        Link("#\(pr.number) \(pr.title)", destination: pr.url).font(.caption).lineLimit(1)
                        Spacer()
                        Text(pr.author).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(6)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func changes(_ r: GitRepoStatus) -> String {
        var parts: [String] = []
        if r.staged > 0 { parts.append("\(r.staged) staged") }
        if r.unstaged > 0 { parts.append("\(r.unstaged) modified") }
        if r.untracked > 0 { parts.append("\(r.untracked) new") }
        if r.conflicts > 0 { parts.append("\(r.conflicts) conflicts") }
        return parts.joined(separator: " · ")
    }

    private var heatmap: some View {
        let weeks = max(8, min(52, context.size.w * 4))
        var cal = Calendar.current
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: Date())!.start
        let maxCount = max(1, vm.heatmap.values.max() ?? 1)
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(vm.heatmap.values.reduce(0, +)) commits in the last year").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: 2) {
                ForEach((0..<weeks).reversed(), id: \.self) { w in
                    VStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: d - w * 7, to: start)!
                            let n = vm.heatmap[day.dayKey] ?? 0
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(day > Date() ? Color.clear : n == 0 ? Color.primary.opacity(0.07) : Color.green.opacity(0.25 + 0.75 * Double(n) / Double(maxCount)))
                                .frame(width: 8, height: 8)
                                .help("\(day.formatted(date: .abbreviated, time: .omitted)): \(n) commits")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Commit heatmap, \(vm.heatmap.values.reduce(0, +)) commits in the last year")
    }
}
