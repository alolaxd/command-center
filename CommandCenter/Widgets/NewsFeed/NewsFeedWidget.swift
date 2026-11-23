import SwiftUI

struct NewsFeedWidget: DashboardWidget {
    static let kind = "news"
    static let title = "News & RSS"
    static let symbol = "newspaper"
    static let summary = "RSS/Atom headlines with a clutter-free reader view, AI daily digest and save-to-Notes."
    static let category = WidgetCategory.information
    static let defaultSize = GridSize(4, 4)
    static let refreshInterval: TimeInterval? = 1800

    let context: WidgetContext<NewsFeedConfiguration>
    @State private var vm = NewsFeedViewModel()
    @State private var showDigest = false

    init(context: WidgetContext<NewsFeedConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(vm.items.filter { !$0.read }.count) unread").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { showDigest = true; if vm.digest == nil { Task { await vm.dailyDigest() } } } label: { Label("Digest", systemImage: "sparkles") }
                    .controlSize(.small)
                Button { Task { await vm.refresh(context.config) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(vm.loading).accessibilityLabel("Refresh feeds")
            }
            List(vm.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.callout.weight(item.read ? .regular : .semibold)).foregroundStyle(item.read ? .secondary : .primary).lineLimit(2)
                    Text("\(item.feedTitle) · \(item.published.formatted(.relative(presentation: .named)))").font(.caption2).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture { Task { await vm.open(item, config: context.config) } }
                .contextMenu {
                    Button("Open in Browser") { if let u = URL(string: item.link) { NSWorkspace.shared.open(u) }; NewsStore.setRead(item.id) }
                    Button(item.read ? "Mark Unread" : "Mark Read") { NewsStore.setRead(item.id, !item.read); vm.load(context.config) }
                    Button("Send to Inbox") { InboxCapture.capture(item.link) }
                }
                .accessibilityElement(children: .combine)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .overlay { if vm.items.isEmpty { if vm.loading { ProgressView() } else { EmptyStateView(symbol: "newspaper", title: "No articles") } } }
        }
        .onAppear { vm.load(context.config) }
        .refreshing(every: Self.refreshInterval) { await vm.refresh(context.config) }
        .onChange(of: context.config) { Task { await vm.refresh(context.config) } }
        .sheet(isPresented: Binding(get: { vm.reader != nil }, set: { if !$0 { vm.reader = nil } })) { readerSheet }
        .sheet(isPresented: $showDigest) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Today in your feeds").font(.headline)
                    Spacer()
                    Button("Regenerate") { Task { await vm.dailyDigest() } }.disabled(vm.digesting)
                    Button("Done") { showDigest = false }.keyboardShortcut(.defaultAction)
                }
                ScrollView { if vm.digesting { ProgressView() } else { MarkdownView(text: vm.digest ?? "") } }
            }
            .padding().frame(width: 560, height: 520)
        }
    }

    @ViewBuilder private var readerSheet: some View {
        if let r = vm.reader {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(r.item.feedTitle).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Save to Notes") { vm.saveToNotes() }
                    Button("Open in Browser") { if let u = URL(string: r.item.link) { NSWorkspace.shared.open(u) } }
                    Button("Done") { vm.reader = nil }.keyboardShortcut(.defaultAction)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(r.title).font(.title2.bold())
                        if vm.readerLoading { ProgressView() }
                        else if r.paragraphs.isEmpty { Text("Couldn't extract the article. Open it in your browser instead.").foregroundStyle(.secondary) }
                        else { MarkdownView(text: r.paragraphs.joined(separator: "\n\n")) }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                }
            }
            .padding()
            .frame(width: 700, height: 640)
        }
    }
}
