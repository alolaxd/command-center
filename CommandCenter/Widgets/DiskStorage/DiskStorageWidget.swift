import SwiftUI

struct DiskStorageWidget: DashboardWidget {
    static let kind = "disk"
    static let title = "Disk & Storage"
    static let symbol = "internaldrive"
    static let summary = "Treemap of folder sizes, largest files, trash size with empty, and mounted drives with eject."
    static let category = WidgetCategory.system
    static let defaultSize = GridSize(4, 4)

    let context: WidgetContext<DiskStorageConfiguration>
    @State private var vm = DiskStorageViewModel()
    @State private var tab = 0
    @State private var confirmEmpty = false

    init(context: WidgetContext<DiskStorageConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.volumes.filter(\.isInternal).prefix(1)) { v in volumeRow(v) }
            Picker("", selection: $tab) { Text("Treemap").tag(0); Text("Largest Files").tag(1); Text("Drives").tag(2) }
                .pickerStyle(.segmented).labelsHidden()
            switch tab {
            case 0: treemap
            case 1: largest
            default: drives
            }
            HStack {
                Label(vm.trash.map { "Trash: \($0.bytes)" } ?? "Trash: needs Full Disk Access", systemImage: "trash").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Empty Trash") { confirmEmpty = true }.controlSize(.small).disabled(vm.trash == 0)
            }
        }
        .task(id: context.config.root) { vm.drillPath = nil; await vm.load(context.config) }
        .confirmationDialog("Permanently erase the items in the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    if let err = await DiskStorageStore.emptyTrash() { WidgetBus.shared.toast(err) }
                    vm.trash = await DiskStorageStore.trashSize()
                }
            }
        }
    }

    private func volumeRow(_ v: VolumeInfo) -> some View {
        let used = Double(v.total - v.available) / Double(max(1, v.total))
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(v.name).font(.caption.weight(.semibold))
                Spacer()
                Text("\(v.available.bytes) free of \(v.total.bytes)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            MeterBar(fraction: used, tint: used > 0.9 ? .red : used > 0.75 ? .orange : .blue)
        }
    }

    private var treemap: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if vm.drillPath != nil {
                    Button { Task { await vm.up(context.config) } } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                }
                Text((vm.drillPath ?? (context.config.root as NSString).expandingTildeInPath as String).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Spacer()
                Button { Task { await vm.scan(vm.drillPath ?? (context.config.root as NSString).expandingTildeInPath) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(vm.scanning).accessibilityLabel("Rescan")
            }
            if vm.scanning || vm.result == nil {
                VStack { ProgressView(); Text("Scanning \(vm.progress)…").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let r = vm.result {
                GeometryReader { geo in
                    let items = Array(r.children.prefix(24))
                    let palette: [Color] = [.blue, .purple, .teal, .orange, .green, .pink, .indigo, .brown]
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(DiskStorageStore.treemap(items, in: CGRect(origin: .zero, size: geo.size)).enumerated()), id: \.offset) { i, pair in
                            let (item, rect) = pair
                            RoundedRectangle(cornerRadius: 3)
                                .fill(palette[i % palette.count].opacity(0.55))
                                .overlay(alignment: .topLeading) {
                                    if rect.width > 50 && rect.height > 26 {
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(item.name).font(.caption2.weight(.semibold)).lineLimit(1)
                                            Text(item.size.bytes).font(.system(size: 9)).foregroundStyle(.secondary)
                                        }.padding(3)
                                    }
                                }
                                .frame(width: max(0, rect.width - 2), height: max(0, rect.height - 2))
                                .offset(x: rect.minX, y: rect.minY)
                                .onTapGesture(count: 2) { Task { await vm.drill(item, config: context.config) } }
                                .help("\(item.name) — \(item.size.bytes)\(item.isDirectory ? " (double-click to open)" : "")")
                                .contextMenu { Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } }
                                .accessibilityLabel("\(item.name), \(item.size.bytes)")
                        }
                    }
                }
            }
        }
    }

    private var largest: some View {
        List(vm.result?.largestFiles ?? []) { f in
            HStack {
                Image(nsImage: NSWorkspace.shared.icon(forFile: f.path)).resizable().frame(width: 16, height: 16)
                VStack(alignment: .leading) {
                    Text(f.name).font(.caption).lineLimit(1)
                    Text((f.path as NSString).deletingLastPathComponent.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                }
                Spacer()
                Text(f.size.bytes).font(.caption.monospacedDigit())
            }
            .contextMenu {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f.path)]) }
                Button("Move to Trash", role: .destructive) { try? FileManager.default.trashItem(at: URL(fileURLWithPath: f.path), resultingItemURL: nil) }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
    }

    private var drives: some View {
        List(vm.volumes) { v in
            HStack {
                Image(systemName: v.isInternal ? "internaldrive" : "externaldrive").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(v.name).font(.caption.weight(.medium))
                    MeterBar(fraction: Double(v.total - v.available) / Double(max(1, v.total)), height: 4)
                    Text("\(v.available.bytes) free of \(v.total.bytes)").font(.caption2).foregroundStyle(.secondary)
                }
                if !v.isInternal || v.isRemovable {
                    Button { if let e = DiskStorageStore.eject(v) { WidgetBus.shared.toast(e) } else { vm.volumes = DiskStorageStore.volumes() } } label: {
                        Image(systemName: "eject")
                    }.buttonStyle(.borderless).accessibilityLabel("Eject \(v.name)")
                }
            }
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
    }
}
