import SwiftUI

struct AgentMonitorWidget: DashboardWidget {
    static let kind = "agents"
    static let title = "AI Agent Monitor"
    static let symbol = "cpu.fill"
    static let summary = "Live status, tokens and estimated cost for Claude Code, OpenCode, Codex, Aider and custom agents."
    static let category = WidgetCategory.aiDev
    static let minSize = GridSize(3, 3)
    static let defaultSize = GridSize(6, 4)
    static let refreshInterval: TimeInterval? = 10

    let context: WidgetContext<AgentMonitorConfiguration>
    @State private var vm = AgentMonitorViewModel()
    @State private var tab = 0
    @State private var confirmKill: AgentScanner.AgentProcess?

    init(context: WidgetContext<AgentMonitorConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            costStrip
            Picker("", selection: $tab) {
                Text("Active (\(vm.sessions.count + vm.custom.filter(\.alive).count))").tag(0)
                Text("Processes (\(vm.processes.count))").tag(1)
                if context.config.showHistory { Text("History").tag(2) }
                Text("By Provider").tag(3)
            }
            .pickerStyle(.segmented).labelsHidden()
            switch tab {
            case 0: activeList
            case 1: processList
            case 2: historyList
            default: providerBreakdown
            }
        }
        .refreshing(every: Self.refreshInterval) {
            // First appearance: make sure logs/processes have been scanned at least once.
            if AgentActivity.lastScan == nil { await vm.rescan(context.config) } else { vm.load(context.config) }
        }
        .onReceive(WidgetBus.shared.events) { e in if case .dataChanged("agents") = e { vm.load(context.config) } }
        .onChange(of: context.config) { Task { await vm.rescan(context.config) } }
        .confirmationDialog("Terminate \(confirmKill?.provider.rawValue ?? "agent") (pid \(confirmKill?.pid ?? 0))?",
                            isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } })) {
            Button("Terminate (SIGTERM)") { if let p = confirmKill { SystemSampler.kill(p.pid); refreshSoon() } }
            Button("Force Kill (SIGKILL)", role: .destructive) { if let p = confirmKill { SystemSampler.kill(p.pid, force: true); refreshSoon() } }
        }
    }

    private var costStrip: some View {
        HStack(spacing: 10) {
            StatTile(label: "Today", value: vm.total(vm.costToday).usd)
            StatTile(label: "This week", value: vm.total(vm.costWeek).usd)
            StatTile(label: "This month", value: vm.total(vm.costMonth).usd)
            StatTile(label: "All time", value: vm.total(vm.costAll).usd)
            Button { Task { await vm.rescan(context.config) } } label: {
                Image(systemName: "arrow.clockwise").rotationEffect(.degrees(vm.scanning ? 360 : 0))
                    .animation(vm.scanning ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: vm.scanning)
            }
            .buttonStyle(.borderless).help("Rescan logs").accessibilityLabel("Rescan")
        }
    }

    private var activeList: some View {
        List {
            ForEach(vm.sessions) { s in sessionRow(s, showKill: true) }
            ForEach(vm.custom.filter(\.alive)) { c in
                HStack {
                    statusDot(.running)
                    Image(systemName: AgentProvider.custom.symbol).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(c.name).font(.callout.weight(.medium))
                        Text(c.task).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if let pid = c.pid {
                        Button { SystemSampler.kill(pid); refreshSoon() } label: { Image(systemName: "stop.circle") }
                            .buttonStyle(.borderless).foregroundStyle(.red).accessibilityLabel("Kill \(c.name)")
                    }
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .overlay { if vm.sessions.isEmpty && !vm.custom.contains(where: \.alive) { EmptyStateView(symbol: "moon.zzz", title: "No agents running") } }
    }

    private func sessionRow(_ s: AgentSession, showKill: Bool) -> some View {
        let status = AgentStatus.of(s, processes: vm.processes)
        return HStack(alignment: .top, spacing: 8) {
            statusDot(status).padding(.top, 5)
            Image(systemName: s.provider.symbol).foregroundStyle(.secondary).frame(width: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.callout.weight(.medium)).lineLimit(1)
                Text(s.lastEvent.isEmpty ? (s.cwd as NSString).abbreviatingWithTildeInPath : s.lastEvent)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 8) {
                    Text(s.provider.rawValue)
                    Text(s.model.isEmpty ? "—" : s.model)
                    Text("\(s.totalTokens.formatted(.number.notation(.compactName))) tok")
                    Text(s.duration.compactDuration)
                    Text(status.rawValue)
                }
                .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text(s.cost.usd).font(.callout.monospacedDigit())
            if showKill, let p = vm.process(for: s) {
                Button { confirmKill = p } label: { Image(systemName: "stop.circle") }
                    .buttonStyle(.borderless).foregroundStyle(.red).help("Terminate agent").accessibilityLabel("Kill agent")
            }
        }
        .contextMenu {
            Button("Open Folder in Terminal Pane") { WidgetBus.shared.publish(.runInTerminal("cd \(shellQuote(s.cwd))")) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: s.cwd)]) }
            Button("Copy Title") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s.title, forType: .string) }
        }
        .accessibilityElement(children: .combine)
    }

    private var processList: some View {
        List(vm.processes) { p in
            HStack {
                Image(systemName: p.provider.symbol).foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    Text("\(p.provider.rawValue) · pid \(p.pid)").font(.callout)
                    Text((p.cwd as NSString).abbreviatingWithTildeInPath).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Kill") { confirmKill = p }.controlSize(.small)
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .overlay { if vm.processes.isEmpty { EmptyStateView(symbol: "checkmark.circle", title: "No agent processes") } }
    }

    private var historyList: some View {
        VStack(spacing: 4) {
            SearchField(text: Binding(get: { vm.query }, set: { vm.query = $0; vm.load(context.config) }), prompt: "Search sessions")
            List(vm.history) { s in sessionRow(s, showKill: false) }
                .listStyle(.plain).scrollContentBackground(.hidden)
        }
    }

    private var providerBreakdown: some View {
        ScrollView {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Provider"); Text("Today"); Text("Week"); Text("Month"); Text("All time")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(AgentProvider.allCases) { p in
                    let all = vm.costAll.first { $0.provider == p }
                    if all != nil {
                        GridRow {
                            Label(p.rawValue, systemImage: p.symbol)
                            Text((vm.costToday.first { $0.provider == p }?.cost ?? 0).usd)
                            Text((vm.costWeek.first { $0.provider == p }?.cost ?? 0).usd)
                            Text((vm.costMonth.first { $0.provider == p }?.cost ?? 0).usd)
                            Text((all?.cost ?? 0).usd)
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }
            Text("Costs are estimates from token counts and list prices (OpenCode reports its own cost).")
                .font(.caption2).foregroundStyle(.tertiary).padding(.top, 6)
        }
    }

    private func statusDot(_ s: AgentStatus) -> some View {
        Circle().fill(s == .running ? Color.green : s == .waiting ? Color.orange : Color.gray).frame(width: 7, height: 7)
            .accessibilityLabel(s.rawValue)
    }

    private func refreshSoon() { Task { try? await Task.sleep(for: .seconds(1)); await vm.rescan(context.config) } }
    private func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}
