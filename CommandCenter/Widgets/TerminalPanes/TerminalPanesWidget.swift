import SwiftUI

struct TerminalPanesWidget: DashboardWidget {
    static let kind = "terminal"
    static let title = "Terminal"
    static let symbol = "apple.terminal"
    static let summary = "Persistent tabbed terminals (real PTYs) with splits, search, clickable paths/URLs and drag-in snippets."
    static let category = WidgetCategory.aiDev
    static let minSize = GridSize(3, 2)
    static let defaultSize = GridSize(6, 4)

    let context: WidgetContext<TerminalPanesConfiguration>
    @State private var vm = TerminalPanesViewModel()

    init(context: WidgetContext<TerminalPanesConfiguration>) { self.context = context }

    private var config: TerminalPanesConfiguration { context.config }

    var body: some View {
        VStack(spacing: 4) {
            tabBar
            if vm.showSearch {
                HStack {
                    SearchField(text: $vm.search, prompt: "Find in output").onSubmit { vm.find(config) }
                    Button { vm.find(config, backwards: true) } label: { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                    Button { vm.find(config) } label: { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                    Button { vm.showSearch = false } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
            }
            if let tab = vm.selectedTab(config) {
                panes(tab).id(tab.id)
            }
        }
        .onReceive(WidgetBus.shared.events) { e in
            switch e {
            case .dataChanged("terminal.newTab"): vm.newTab(config, update: context.updateConfig)
            case .runInTerminal(let cmd): vm.activeSession(config)?.runLine(cmd)
            default: break
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(config.tabs.enumerated()), id: \.element.id) { i, tab in
                        let selected = tab.id == vm.selectedTab(config)?.id
                        HStack(spacing: 4) {
                            Text(tab.title.isEmpty ? TerminalPanesStore.session(for: tab.panes[0]).title : tab.title)
                                .font(.caption).lineLimit(1).frame(maxWidth: 140)
                            Button { vm.closeTab(tab, config, update: context.updateConfig) } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close tab")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(selected ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(Rectangle())
                        .onTapGesture { var c = config; c.selected = tab.id; context.updateConfig(c) }
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityLabel("Tab \(i + 1)")
                    }
                }
            }
            Button { vm.newTab(config, update: context.updateConfig) } label: { Image(systemName: "plus") }
                .buttonStyle(.borderless).help("New tab (⌘⇧T)").accessibilityLabel("New tab")
            Divider().frame(height: 14)
            Button { vm.split(.horizontal, config, update: context.updateConfig) } label: { Image(systemName: "rectangle.split.2x1") }
                .buttonStyle(.borderless).help("Split side by side")
            Button { vm.split(.vertical, config, update: context.updateConfig) } label: { Image(systemName: "rectangle.split.1x2") }
                .buttonStyle(.borderless).help("Split top/bottom")
            if vm.selectedTab(config)?.split != TerminalTab.Split.none {
                Button { vm.split(.none, config, update: context.updateConfig) } label: { Image(systemName: "rectangle") }
                    .buttonStyle(.borderless).help("Unsplit")
            }
            Button { vm.showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless).help("Find")
        }
    }

    @ViewBuilder
    private func panes(_ tab: TerminalTab) -> some View {
        switch tab.split {
        case .none: pane(tab.panes[0])
        case .horizontal: HSplitView { ForEach(tab.panes) { pane($0) } }
        case .vertical: VSplitView { ForEach(tab.panes) { pane($0) } }
        }
    }

    private func pane(_ p: TerminalPane) -> some View {
        TerminalHostView(session: TerminalPanesStore.session(for: p))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(vm.focusedPane == p.id ? Color.accentColor.opacity(0.5) : .clear))
            .simultaneousGesture(TapGesture().onEnded { vm.focusedPane = p.id })
            .frame(minWidth: 80, minHeight: 60)
            .accessibilityLabel("Terminal")
    }
}
