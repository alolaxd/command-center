import SwiftUI

struct APIHealthWidget: DashboardWidget {
    static let kind = "apihealth"
    static let title = "API Health"
    static let symbol = "waveform.path.ecg"
    static let summary = "Pings your endpoints on an interval: status, latency, uptime sparkline and down alerts."
    static let category = WidgetCategory.aiDev
    static let defaultSize = GridSize(4, 3)

    let context: WidgetContext<APIHealthConfiguration>
    @State private var vm = APIHealthViewModel()
    @State private var newURL = ""

    init(context: WidgetContext<APIHealthConfiguration>) { self.context = context }

    private var anyDown: Bool { context.config.endpoints.contains { vm.history[$0.id]?.last?.ok == false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if context.config.endpoints.isEmpty {
                EmptyStateView(symbol: "waveform.path.ecg", title: "No endpoints", message: "Add a URL to start monitoring.")
            } else {
                HStack {
                    Label(anyDown ? "Issues detected" : "All systems operational", systemImage: anyDown ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(anyDown ? .red : .green)
                    Spacer()
                    Button { Task { await vm.checkNow(context.config) } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless).accessibilityLabel("Check now")
                }
                ScrollView {
                    VStack(spacing: 8) { ForEach(context.config.endpoints) { endpointRow($0) } }
                }
            }
            AddField(prompt: "https://api.example.com/health") { url in
                var c = context.config
                let host = URL(string: url)?.host ?? url
                c.endpoints.append(APIEndpoint(name: host, url: url.hasPrefix("http") ? url : "https://" + url))
                context.updateConfig(c)
            }
        }
        .padding(2)
        .background(anyDown ? Color.red.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .onAppear { vm.sync(context.config); Task { await vm.checkNow(context.config) } }
        .onChange(of: context.config) { vm.sync(context.config) }
        .onReceive(WidgetBus.shared.events) { e in if case .dataChanged("apihealth") = e { vm.load(context.config) } }
    }

    private func endpointRow(_ ep: APIEndpoint) -> some View {
        let h = vm.history[ep.id] ?? []
        let last = h.last
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Circle().fill(last == nil ? Color.gray : last!.ok ? .green : .red).frame(width: 8, height: 8)
                Text(ep.name).font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
                if let last {
                    Text(last.status == 0 ? "ERR" : "\(last.status)").font(.caption.monospacedDigit()).foregroundStyle(last.ok ? Color.secondary : .red)
                    Text("\(Int(last.latencyMs)) ms").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 1) {
                ForEach(Array(h.suffix(40).enumerated()), id: \.offset) { _, c in
                    RoundedRectangle(cornerRadius: 1).fill(c.ok ? Color.green.opacity(0.7) : .red).frame(height: 10)
                }
            }
            .accessibilityHidden(true)
            HStack {
                Sparkline(values: h.map(\.latencyMs), color: .blue, lineWidth: 1).frame(height: 14)
                if let up = APIHealthStore.uptime(ep.id) { Text("\(String(format: "%.1f", up * 100))% up").font(.caption2).foregroundStyle(.secondary) }
            }
            if let err = last?.error { Text(err).font(.caption2).foregroundStyle(.red).lineLimit(1) }
        }
        .contextMenu {
            Button("Open URL") { if let u = URL(string: ep.url) { NSWorkspace.shared.open(u) } }
            Button("Remove", role: .destructive) {
                var c = context.config; c.endpoints.removeAll { $0.id == ep.id }; context.updateConfig(c)
                APIHealthStore.endpoints.removeAll { $0.id == ep.id }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ep.name), \(last?.ok == false ? "down" : "up")")
    }
}
