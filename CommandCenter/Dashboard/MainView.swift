import LocalAuthentication
import SwiftUI

struct MainView: View {
    @AppStorage(SettingsKey.showSidebar) private var showSidebar = false
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showGallery = false
    @State private var locked = UserDefaults.standard.bool(forKey: SettingsKey.appLock)
    @State private var renameTarget: Workspace?
    @State private var renameText = ""
    @State private var deleteTarget: Workspace?
    @State private var showManager = false
    @Namespace private var switcherNS
    private var store: WorkspaceStore { .shared }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            ZStack {
                if store.workspaces.isEmpty {
                    EmptyStateView(symbol: "rectangle.stack.badge.plus", title: "No workspaces",
                                   message: "Create a workspace, or add one of the layout presets.",
                                   action: ("New Workspace", { store.addWorkspace(name: "Workspace 1") }))
                } else if let ws = store.current {
                    if let zenID = store.zenWidgetID, let inst = ws.widgets.first(where: { $0.id == zenID }) {
                        ZenView(instance: inst)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    } else {
                        DashboardView(workspace: ws)
                            .id(ws.id)
                            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                    removal: .opacity))
                    }
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.86), value: store.selectedID)
            .animation(.spring(response: 0.35), value: store.zenWidgetID)
            .overlay(alignment: .bottomTrailing) { ToastOverlay() }
            .toolbar { toolbarContent }
            .navigationTitle(store.current?.name ?? "Command Center")
        }
        .onAppear { columnVisibility = showSidebar ? .all : .detailOnly }
        .onChange(of: showSidebar) { _, v in withAnimation { columnVisibility = v ? .all : .detailOnly } }
        .onChange(of: columnVisibility) { _, v in showSidebar = (v != .detailOnly) }
        .confirmationDialog("Delete “\(deleteTarget?.name ?? "")”?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Delete Workspace", role: .destructive) { if let t = deleteTarget { withAnimation { store.deleteWorkspace(t.id) } }; deleteTarget = nil }
        } message: {
            Text("Its \(deleteTarget?.widgets.count ?? 0) widgets and their settings will be removed. Your notes, reminders and other data are kept.")
        }
        .sheet(isPresented: $showManager) { WorkspaceManagerView(onDelete: { deleteTarget = $0 }) }
        .onReceive(NotificationCenter.default.publisher(for: .manageWorkspaces)) { _ in showManager = true }
        .onReceive(NotificationCenter.default.publisher(for: .deleteCurrentWorkspace)) { _ in deleteTarget = store.current }
        .alert("Rename Workspace", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") { if let t = renameTarget { store.renameWorkspace(t.id, to: renameText) }; renameTarget = nil }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .sheet(isPresented: $showGallery) { WidgetGalleryView() }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { onboarded = !$0 })) { OnboardingView() }
        .overlay { if locked { LockView(locked: $locked) } }
        .background(SwipeCatcher { store.selectNext($0) })
        .onReceive(NotificationCenter.default.publisher(for: .showWidgetGallery)) { _ in showGallery = true }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 2) {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { idx, ws in
                    let selected = ws.id == store.current?.id
                    Button { store.select(ws.id) } label: {
                        Label(ws.name, systemImage: ws.symbol)
                            .labelStyle(.titleAndIcon)
                            .font(.callout)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background {
                                if selected {
                                    Capsule().fill(.quaternary).matchedGeometryEffect(id: "ws", in: switcherNS)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(idx < 9 ? "\(ws.name) (⌘\(idx + 1))" : ws.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .contextMenu { workspaceMenu(ws) }
                }
                Button { store.addWorkspace(name: "Workspace \(store.workspaces.count + 1)") } label: {
                    Image(systemName: "plus").font(.caption).padding(4)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("New Workspace").accessibilityLabel("New Workspace")
                Menu {
                    if let ws = store.current { workspaceMenu(ws) }
                    Divider()
                    Button("Manage Workspaces…") { showManager = true }
                } label: { Image(systemName: "chevron.down").font(.caption2) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Workspace options").accessibilityLabel("Workspace options")
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.selectedID)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { withAnimation { showSidebar.toggle() } } label: { Label("Widget List", systemImage: "sidebar.left") }
                .help("Show or hide the widget list (⌃⌘S)")
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button { withAnimation(.spring(response: 0.35)) { store.tidyUp() } } label: { Label("Tidy Up", systemImage: "rectangle.3.group") }
                .help("Close gaps in the layout (⌘⇧L)")
            Button { showGallery = true } label: { Label("Add Widget", systemImage: "plus") }
                .help("Add Widget (⌘⇧W)")
            Button { withAnimation { store.toggleZen() } } label: {
                Label("Zen Mode", systemImage: store.zenWidgetID == nil ? "viewfinder" : "rectangle.grid.2x2")
            }
            .help("Zen Mode (⌘⇧Z)")
        }
    }
}

extension MainView {
    @ViewBuilder func workspaceMenu(_ ws: Workspace) -> some View {
        Button("Rename…") { renameText = ws.name; renameTarget = ws }
        Menu("Icon") {
            ForEach(["house", "chevron.left.forwardslash.chevron.right", "chart.line.uptrend.xyaxis", "heart",
                     "briefcase", "book", "gamecontroller", "server.rack", "sparkles", "scope"], id: \.self) { sym in
                Button { setSymbol(ws.id, sym) } label: { Label(sym, systemImage: sym) }
            }
        }
        if let i = store.workspaces.firstIndex(of: ws) {
            Button("Move Left") { store.moveWorkspace(from: [i], to: i - 1) }.disabled(i == 0)
            Button("Move Right") { store.moveWorkspace(from: [i], to: i + 2) }.disabled(i == store.workspaces.count - 1)
        }
        Divider()
        Button("Delete “\(ws.name)”…", role: .destructive) { deleteTarget = ws }
    }

    private func setSymbol(_ id: UUID, _ symbol: String) {
        guard let i = store.workspaces.firstIndex(where: { $0.id == id }) else { return }
        store.workspaces[i].symbol = symbol
        store.scheduleSave()
    }
}

struct ZenView: View {
    let instance: WidgetInstance
    var body: some View {
        WidgetCardView(instance: instance, isFocused: false, isDragging: false, isZen: true, onMove: { _ in }, onResize: { _ in })
            .padding(24)
            .onExitCommand { withAnimation { WorkspaceStore.shared.zenWidgetID = nil } }
    }
}

/// Toasts published on the WidgetBus by any widget.
struct ToastOverlay: View {
    struct Toast: Identifiable { let id = UUID(); let text: String; let symbol: String }
    @State private var toasts: [Toast] = []

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ForEach(toasts) { t in
                Label(t.text, systemImage: t.symbol)
                    .font(.callout)
                    .lineLimit(2)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(maxWidth: 380, alignment: .trailing)
        .onReceive(WidgetBus.shared.events) { event in
            guard case .toast(let text, let symbol) = event else { return }
            let toast = Toast(text: text, symbol: symbol)
            withAnimation(.spring) { toasts.append(toast) }
            if toasts.count > 4 { toasts.removeFirst() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation(.spring) { toasts.removeAll { $0.id == toast.id } }
            }
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }
}

/// Touch ID / password gate when App Lock is enabled.
struct LockView: View {
    @Binding var locked: Bool
    @State private var error: String?
    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "lock").font(.largeTitle)
                Text("Command Center is locked").font(.headline)
                if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                Button("Unlock with Touch ID") { authenticate() }.keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: authenticate)
    }

    private func authenticate() {
        let ctx = LAContext()
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock Command Center") { ok, err in
            DispatchQueue.main.async {
                if ok { withAnimation { locked = false } } else { error = err?.localizedDescription }
            }
        }
    }
}

/// Catches trackpad swipe events to switch workspaces.
struct SwipeCatcher: NSViewRepresentable {
    let onSwipe: (Int) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .swipe) { event in
            if event.deltaX != 0, event.window?.identifier?.rawValue.contains("main") ?? true {
                onSwipe(event.deltaX > 0 ? -1 : 1)
            }
            return event
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var monitor: Any?; deinit { if let monitor { NSEvent.removeMonitor(monitor) } } }
}

extension Notification.Name {
    static let showWidgetGallery = Notification.Name("cc.showWidgetGallery")
    static let exportLayout = Notification.Name("cc.exportLayout")
    static let manageWorkspaces = Notification.Name("cc.manageWorkspaces")
    static let deleteCurrentWorkspace = Notification.Name("cc.deleteCurrentWorkspace")
    static let importLayout = Notification.Name("cc.importLayout")
}

/// Lists every workspace (including the defaults) for renaming, reordering and deletion.
struct WorkspaceManagerView: View {
    var onDelete: (Workspace) -> Void
    @Environment(\.dismiss) private var dismiss
    private var store: WorkspaceStore { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Workspaces").font(.title2.bold())
            List {
                ForEach(store.workspaces) { ws in
                    HStack {
                        Image(systemName: ws.symbol).frame(width: 22)
                        TextField("Name", text: Binding(get: { ws.name }, set: { store.renameWorkspace(ws.id, to: $0) }))
                            .textFieldStyle(.plain)
                        Text("\(ws.widgets.count) widgets").font(.caption).foregroundStyle(.secondary)
                        Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { onDelete(ws) } } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless).foregroundStyle(.red).help("Delete \(ws.name)")
                        .accessibilityLabel("Delete \(ws.name)")
                    }
                }
                .onMove { store.moveWorkspace(from: $0, to: $1) }
            }
            .frame(minHeight: 220)
            .overlay { if store.workspaces.isEmpty { Text("No workspaces").foregroundStyle(.secondary) } }
            HStack {
                Button("New Workspace") { store.addWorkspace(name: "Workspace \(store.workspaces.count + 1)") }
                Menu("Add Preset") {
                    ForEach(WorkspacePresets.presets, id: \.0) { name, ws in Button(name) { store.applyPreset(ws) } }
                    Divider()
                    Button("Restore Default Workspaces") { WorkspacePresets.defaults().forEach(store.applyPreset) }
                }
                .fixedSize()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460, height: 400)
    }
}
