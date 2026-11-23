import SwiftUI

struct ShortcutsLauncherWidget: DashboardWidget {
    static let kind = "shortcuts"
    static let title = "Launcher"
    static let symbol = "square.grid.3x3.square"
    static let summary = "Buttons for macOS Shortcuts, shell scripts, AppleScripts, URLs and apps — drag to reorder."
    static let category = WidgetCategory.utility
    static let defaultSize = GridSize(4, 3)

    let context: WidgetContext<ShortcutsLauncherConfiguration>
    @State private var vm = ShortcutsLauncherViewModel()
    @State private var editing: LauncherItem?
    @State private var confirm: LauncherItem?

    init(context: WidgetContext<ShortcutsLauncherConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: context.config.tileSize), spacing: 8)], spacing: 8) {
                    ForEach(vm.items) { i in tile(i) }
                    Button { editing = LauncherItem(kind: .shortcut, label: "New", value: "", position: Double(vm.items.count)) } label: {
                        VStack { Image(systemName: "plus").font(.title2); Text("Add").font(.caption2) }
                            .frame(width: context.config.tileSize, height: context.config.tileSize)
                            .background(RoundedRectangle(cornerRadius: 12).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundStyle(.tertiary))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Add launcher button")
                }
            }
            if let out = vm.lastOutput {
                Text(out).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(3).onTapGesture { vm.lastOutput = nil }
            }
        }
        .onAppear { vm.load() }
        .sheet(item: $editing) { i in LauncherItemEditor(item: i, vm: vm) }
        .confirmationDialog("Run “\(confirm?.label ?? "")”?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } })) {
            Button("Run") { if let c = confirm { Task { await vm.run(c) } } }
        } message: { Text(confirm?.value ?? "") }
    }

    private func tile(_ i: LauncherItem) -> some View {
        let size = context.config.tileSize
        return Button {
            if i.kind == .shell && context.config.confirmShell { confirm = i } else { Task { await vm.run(i) } }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    if vm.running.contains(i.id) { ProgressView().controlSize(.small) }
                    else { Image(systemName: i.symbol).font(.system(size: size * 0.3)).foregroundStyle(.white) }
                }
                Text(i.label).font(.caption2.weight(.medium)).foregroundStyle(.white).lineLimit(1)
            }
            .frame(width: size, height: size)
            .background(Palette.color(i.color).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help("\(i.kind.rawValue): \(i.value)")
        .draggable(i.id)
        .dropDestination(for: String.self) { ids, _ in if let id = ids.first { vm.move(id, before: i.id) }; return true }
        .contextMenu {
            Button("Edit…") { editing = i }
            Button("Delete", role: .destructive) { ShortcutsStore.delete(i); vm.load() }
        }
        .accessibilityLabel("\(i.label), \(i.kind.rawValue)")
    }
}

struct LauncherItemEditor: View {
    @State var item: LauncherItem
    let vm: ShortcutsLauncherViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Picker("Type", selection: $item.kind) { ForEach(LauncherItem.Kind.allCases, id: \.self) { Text($0.rawValue) } }
            TextField("Label", text: $item.label)
            switch item.kind {
            case .shortcut:
                Picker("Shortcut", selection: $item.value) {
                    Text("Choose…").tag("")
                    ForEach(vm.systemShortcuts, id: \.self) { Text($0).tag($0) }
                }
                .task { await vm.loadSystemShortcuts() }
            case .app:
                HStack {
                    TextField("App path", text: $item.value)
                    Button("Choose…") {
                        let p = NSOpenPanel(); p.allowedContentTypes = [.application]; p.directoryURL = URL(fileURLWithPath: "/Applications")
                        if p.runModal() == .OK, let u = p.url { item.value = u.path; if item.label == "New" { item.label = u.deletingPathExtension().lastPathComponent } }
                    }
                }
            default:
                TextField(item.kind == .url ? "https://…" : "Script", text: $item.value, axis: .vertical).lineLimit(1...6)
                    .font(item.kind == .url ? .body : .body.monospaced())
            }
            TextField("SF Symbol", text: $item.symbol)
            LabeledContent("Color") { PalettePicker(selection: $item.color) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { ShortcutsStore.save(item); vm.load(); dismiss() }.keyboardShortcut(.defaultAction).disabled(item.value.isEmpty)
            }
        }
        .padding().frame(width: 420)
    }
}
