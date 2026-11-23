import SwiftUI

/// Optional translucent panel listing the current workspace's widgets for quick on/off.
/// Workspace switching lives only in the toolbar, so this panel never duplicates it.
struct SidebarView: View {
    private var store: WorkspaceStore { .shared }

    var body: some View {
        List {
            if let ws = store.current {
                Section("Widgets in \(ws.name)") {
                    ForEach(ws.widgets) { inst in
                        if let d = WidgetRegistry.descriptor(inst.kind) {
                            HStack {
                                Label(d.title, systemImage: d.symbol).foregroundStyle(inst.isHidden ? .secondary : .primary)
                                Spacer()
                                Toggle("", isOn: Binding(get: { !inst.isHidden }, set: { _ in withAnimation { store.toggleHidden(inst.id) } }))
                                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                                    .accessibilityLabel("Show \(d.title)")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { store.focusedWidgetID = inst.id; withAnimation { store.toggleZen() } }
                            .contextMenu {
                                Button("Focus in Zen Mode") { store.focusedWidgetID = inst.id; withAnimation { store.toggleZen() } }
                                Button("Remove", role: .destructive) { withAnimation { store.removeWidget(inst.id) } }
                            }
                        }
                    }
                }
            }
            Button { NotificationCenter.default.post(name: .showWidgetGallery, object: nil) } label: {
                Label("Add Widget…", systemImage: "plus")
            }
            .buttonStyle(.borderless).foregroundStyle(.secondary)
        }
        .listStyle(.sidebar)
    }
}

struct WidgetGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add Widget").font(.title2.bold())
                Spacer()
                SearchField(text: $query, prompt: "Search widgets").frame(width: 220)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(WidgetRegistry.grouped(), id: \.0) { category, items in
                        let filtered = items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.summary.localizedCaseInsensitiveContains(query) }
                        if !filtered.isEmpty {
                            Text(category.rawValue).font(.headline)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                                ForEach(filtered) { d in
                                    Button {
                                        withAnimation(.spring) { _ = WorkspaceStore.shared.addWidget(kind: d.kind) }
                                        WidgetBus.shared.toast("Added \(d.title)", symbol: d.symbol)
                                    } label: {
                                        HStack(alignment: .top, spacing: 10) {
                                            Image(systemName: d.symbol).font(.title3).frame(width: 28)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(d.title).font(.callout.weight(.semibold))
                                                Text(d.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                                Text("\(d.defaultSize.w)×\(d.defaultSize.h)").font(.caption2).foregroundStyle(.tertiary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Add \(d.title)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
    }
}
