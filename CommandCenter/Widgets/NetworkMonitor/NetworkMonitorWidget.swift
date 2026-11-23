import Charts
import SwiftUI

struct NetworkMonitorWidget: DashboardWidget {
    static let kind = "network"
    static let title = "Network"
    static let symbol = "network"
    static let summary = "IP addresses, interface, live bandwidth graph, active connections and ping latency."
    static let category = WidgetCategory.system
    static let defaultSize = GridSize(4, 4)
    static let refreshInterval: TimeInterval? = 2

    let context: WidgetContext<NetworkMonitorConfiguration>
    @State private var vm = NetworkMonitorViewModel()
    private var path: NetworkPathObserver { .shared }

    init(context: WidgetContext<NetworkMonitorConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                StatTile(label: "Interface", value: path.isConnected ? path.interfaceType : "Offline", tint: path.isConnected ? .primary : .red)
                StatTile(label: "↓ Down", value: rate(vm.down.last ?? 0))
                StatTile(label: "↑ Up", value: rate(vm.up.last ?? 0))
            }
            Chart {
                ForEach(Array(vm.down.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", i), y: .value("Bps", v), series: .value("dir", "Down")).foregroundStyle(.green)
                }
                ForEach(Array(vm.up.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", i), y: .value("Bps", v), series: .value("dir", "Up")).foregroundStyle(.blue)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisValueLabel { if let d = v.as(Double.self) { Text(rate(d)).font(.system(size: 8)) } }
            } }
            .frame(height: 60)
            .accessibilityLabel("Bandwidth graph")

            Picker("", selection: $vm.tab) {
                Text("Addresses").tag(0)
                if context.config.showConnections { Text("Connections").tag(1) }
                Text("Ping").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: vm.tab) { if vm.tab == 1 { Task { await vm.loadConnections(context.config) } } }

            switch vm.tab {
            case 0:
                List {
                    if let ip = vm.publicIP { row("Public", ip) }
                    ForEach(vm.addresses, id: \.self) { a in row(a.name, a.address) }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            case 1:
                List(vm.connections) { c in
                    HStack {
                        Text(c.process).font(.caption.weight(.medium)).frame(width: 90, alignment: .leading).lineLimit(1)
                        Text(vm.hostNames[c.remoteHost] ?? c.remoteHost).font(.caption).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(":\(c.remotePort)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .overlay { if vm.connections.isEmpty { ProgressView().controlSize(.small) } }
            default:
                List(context.config.pingHosts, id: \.self) { h in
                    let values = vm.pings[h] ?? []
                    HStack {
                        Text(h).font(.caption).frame(width: 90, alignment: .leading).lineLimit(1)
                        Sparkline(values: values.map { max(0, $0) }, color: .orange, lineWidth: 1).frame(height: 14)
                        Text(values.last.map { $0 < 0 ? "timeout" : String(format: "%.0f ms", $0) } ?? "—")
                            .font(.caption.monospacedDigit()).foregroundStyle((values.last ?? 0) < 0 ? .red : .secondary).frame(width: 56, alignment: .trailing)
                    }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .refreshing(every: Self.refreshInterval) { await vm.refresh(context.config) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label).font(.caption).foregroundStyle(.secondary); Spacer(); Text(value).font(.caption.monospaced()).textSelection(.enabled) }
    }

    private func rate(_ bps: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s" }
}
