import SwiftUI
import UniformTypeIdentifiers

/// Hosts a user-authored JavaScript widget. Includes the editor, preview, gallery and .ccwidget sharing.
struct CustomWidgetHost: DashboardWidget {
    static let kind = "customwidget"
    static let title = "Custom Widget"
    static let symbol = "puzzlepiece.extension"
    static let summary = "Build your own widget in JavaScript with live preview; share as .ccwidget bundles."
    static let category = WidgetCategory.utility
    static let defaultSize = GridSize(3, 2)

    let context: WidgetContext<CustomWidgetConfiguration>
    @State private var vm = CustomWidgetViewModel()
    @State private var showEditor = false
    @State private var showGallery = false

    init(context: WidgetContext<CustomWidgetConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if vm.definition == nil {
                EmptyStateView(symbol: "puzzlepiece.extension", title: "No widget selected", message: "Pick one from the gallery or write your own.",
                               action: ("Open Gallery", { showGallery = true }))
            } else {
                switch vm.result {
                case .success(let node): JSNodeView(node: node).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                case .failure(.message(let m)): Label(m, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                case nil: ProgressView()
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Menu {
                Button("Edit Script…") { showEditor = true }.disabled(vm.definition == nil)
                Button("Gallery…") { showGallery = true }
            } label: { Image(systemName: "chevron.left.forwardslash.chevron.right").font(.caption) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().opacity(0.6)
        }
        .refreshing(every: context.config.refreshSeconds) { vm.load(context.config) }
        .onChange(of: context.config) { vm.load(context.config) }
        .sheet(isPresented: $showEditor) {
            if let d = vm.definition { CustomWidgetEditor(definition: d) { vm.load(context.config) } }
        }
        .sheet(isPresented: $showGallery) {
            CustomWidgetGallery { id in var c = context.config; c.definitionID = id; context.updateConfig(c) }
        }
    }
}

struct JSNodeView: View {
    let node: JSNode
    var body: some View {
        switch node {
        case .text(let s, let style):
            Text(s).font(style == "title" ? .title2.bold() : style == "headline" ? .headline : style == "caption" ? .caption : .body)
        case .stat(let label, let value): StatTile(label: label, value: value)
        case .progress(let v, let label):
            VStack(alignment: .leading, spacing: 2) {
                if let label { Text(label).font(.caption).foregroundStyle(.secondary) }
                MeterBar(fraction: v)
            }
        case .sparkline(let values): Sparkline(values: values).frame(height: 24)
        case .list(let items):
            VStack(alignment: .leading, spacing: 2) { ForEach(Array(items.enumerated()), id: \.offset) { Text($0.element).font(.callout) } }
        case .symbol(let name): Image(systemName: name).font(.title2)
        case .spacer: Spacer()
        case .stack(let horizontal, let children):
            if horizontal {
                HStack(spacing: 8) { ForEach(Array(children.enumerated()), id: \.offset) { JSNodeView(node: $0.element) } }
            } else {
                VStack(alignment: .leading, spacing: 6) { ForEach(Array(children.enumerated()), id: \.offset) { JSNodeView(node: $0.element) } }
            }
        }
    }
}

struct CustomWidgetEditor: View {
    @State var definition: CustomWidgetDef
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preview: Result<JSNode, CustomWidgetError>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $definition.name).font(.headline)
                TextField("Author", text: $definition.author).frame(width: 140)
            }
            HSplitView {
                TextEditor(text: $definition.script)
                    .font(.system(.callout, design: .monospaced))
                    .frame(minWidth: 320)
                    .accessibilityLabel("JavaScript source")
                VStack(alignment: .leading) {
                    Text("Preview").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Group {
                        switch preview {
                        case .success(let n): JSNodeView(node: n)
                        case .failure(.message(let m)): Text(m).font(.caption.monospaced()).foregroundStyle(.red)
                        case nil: EmptyView()
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    Spacer()
                    Text("API: render() returns nodes — text, stat, progress, sparkline, list, symbol, hstack, vstack, spacer. cc.now(), cc.storage.get/set, cc.data.pomodorosToday(), habits(), inboxCount(), spentThisMonth(), agentCostToday().")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.leading, 8)
                .frame(minWidth: 240)
            }
            HStack {
                Button("Export .ccwidget…") {
                    let p = NSSavePanel()
                    p.allowedContentTypes = [UTType(filenameExtension: "ccwidget") ?? .json]
                    p.nameFieldStringValue = definition.name + ".ccwidget"
                    if p.runModal() == .OK, let u = p.url { try? CustomWidgetStore.export(definition, to: u) }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") { CustomWidgetStore.save(definition); onSave(); dismiss() }.keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding()
        .frame(width: 820, height: 560)
        .onAppear(perform: run)
        .onChange(of: definition.script) { run() }
    }

    private func run() { preview = CustomWidgetStore.render(definition.script, widgetID: definition.id) }
}

struct CustomWidgetGallery: View {
    var onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var mine = CustomWidgetStore.all()
    @State private var editing: CustomWidgetDef?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Widget Gallery").font(.title2.bold())
            Text("My widgets").font(.headline)
            if mine.isEmpty { Text("None yet.").foregroundStyle(.secondary).font(.callout) }
            ForEach(mine) { d in
                HStack {
                    Image(systemName: "puzzlepiece.extension")
                    Text(d.name)
                    if !d.author.isEmpty { Text("by \(d.author)").foregroundStyle(.secondary).font(.caption) }
                    Spacer()
                    Button("Edit") { editing = d }
                    Button("Use") { onPick(d.id); dismiss() }
                    Button(role: .destructive) { CustomWidgetStore.delete(d); mine = CustomWidgetStore.all() } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            Divider()
            Text("Built-in samples").font(.headline)
            ForEach(CustomWidgetStore.samples, id: \.0) { name, script in
                HStack {
                    Image(systemName: "sparkles")
                    Text(name)
                    Spacer()
                    Button("Add") { let d = CustomWidgetDef(name: name, author: "Command Center", script: script); CustomWidgetStore.save(d); onPick(d.id); dismiss() }
                }
            }
            Text("Community gallery: coming in a future version. Share widgets today as .ccwidget files.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("New Blank Widget") {
                    let d = CustomWidgetDef(name: "My Widget", script: "function render() {\n  return { type: \"text\", value: \"Hello!\", style: \"title\" };\n}\n")
                    CustomWidgetStore.save(d); mine = CustomWidgetStore.all(); editing = d
                }
                Button("Import .ccwidget…") {
                    let p = NSOpenPanel(); p.allowedContentTypes = [UTType(filenameExtension: "ccwidget") ?? .json, .json]
                    if p.runModal() == .OK, let u = p.url {
                        if let d = try? CustomWidgetStore.importBundle(u) { mine = CustomWidgetStore.all(); onPick(d.id); dismiss() }
                        else { WidgetBus.shared.toast("Not a valid .ccwidget file") }
                    }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560)
        .sheet(item: $editing) { d in CustomWidgetEditor(definition: d) { mine = CustomWidgetStore.all() } }
    }
}
