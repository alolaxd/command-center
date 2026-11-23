import SwiftUI

struct SystemMonitorWidget: DashboardWidget {
    static let kind = "sysmon"
    static let title = "System Monitor"
    static let symbol = "cpu"
    static let summary = "Per-core CPU, memory pressure, GPU, disk I/O, network and top processes with kill."
    static let category = WidgetCategory.system
    static let defaultSize = GridSize(4, 4)
    static let refreshInterval: TimeInterval? = 2

    let context: WidgetContext<SystemMonitorConfiguration>
    @State private var vm = SystemMonitorViewModel()
    @State private var confirmKill: SystemSampler.ProcessSample?

    init(context: WidgetContext<SystemMonitorConfiguration>) { self.context = context }

    var body: some View {
        let s = vm.snap
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // CPU
                metricHeader("CPU", String(format: "%.0f%%", s.cpuTotal * 100), history: vm.cpuHistory, range: 0...1, color: .blue)
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(s.cores.enumerated()), id: \.offset) { i, load in
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5).fill(load > 0.85 ? Color.red : Color.blue.opacity(0.75))
                                .frame(height: max(1, 34 * load))
                        }
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 1.5).fill(.quaternary))
                        .accessibilityLabel("Core \(i + 1)").accessibilityValue("\(Int(load * 100)) percent")
                    }
                }
                .frame(height: 34)

                // Memory
                let memFrac = s.memTotal > 0 ? Double(s.memUsed) / Double(s.memTotal) : 0
                metricHeader("Memory", "\(s.memUsed.bytes) / \(s.memTotal.bytes)", history: vm.memHistory, range: 0...1, color: pressureColor(s.pressure))
                MeterBar(fraction: memFrac, tint: pressureColor(s.pressure))
                HStack {
                    Text("Pressure: \(pressureText(s.pressure))").foregroundStyle(pressureColor(s.pressure))
                    Spacer()
                    Text("App \(s.memApp.bytes) · Wired \(s.memWired.bytes) · Compressed \(s.memCompressed.bytes)").foregroundStyle(.secondary)
                }
                .font(.caption2)

                // GPU, Disk, Network
                if let gpu = s.gpu {
                    metricHeader("GPU", String(format: "%.0f%%", gpu * 100), history: vm.gpuHistory, range: 0...1, color: .purple)
                }
                metricHeader("Disk", "R \(rate(s.diskReadPerSec)) · W \(rate(s.diskWritePerSec))", history: vm.diskHistory, color: .orange)
                metricHeader("Network", "↓ \(rate(s.netInPerSec)) · ↑ \(rate(s.netOutPerSec))", history: vm.netInHistory, color: .green)

                if context.config.showProcesses {
                    Divider()
                    HStack {
                        Text("Top processes").font(.caption.weight(.semibold))
                        Spacer()
                        Picker("", selection: Binding(get: { context.config.sortBy }, set: { var c = context.config; c.sortBy = $0; context.updateConfig(c) })) {
                            ForEach(SystemMonitorConfiguration.SortKey.allCases, id: \.self) { Text($0.rawValue) }
                        }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                    }
                    ForEach(vm.top(context.config)) { p in
                        HStack {
                            Text(p.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text(String(format: "%.1f%%", p.cpu)).font(.caption.monospacedDigit()).frame(width: 50, alignment: .trailing)
                            Text(p.memory.bytes).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                            Button { confirmKill = p } label: { Image(systemName: "xmark.octagon") }
                                .buttonStyle(.borderless).foregroundStyle(.red).help("Quit \(p.name)")
                                .accessibilityLabel("Kill \(p.name)")
                        }
                    }
                }
            }
        }
        .refreshing(every: context.config.interval) { await vm.refresh(context.config) }
        .confirmationDialog("Terminate \(confirmKill?.name ?? "")?", isPresented: Binding(get: { confirmKill != nil }, set: { if !$0 { confirmKill = nil } })) {
            Button("Quit (SIGTERM)") { if let p = confirmKill { SystemSampler.kill(p.pid) } }
            Button("Force Quit (SIGKILL)", role: .destructive) { if let p = confirmKill { SystemSampler.kill(p.pid, force: true) } }
        }
    }

    private func metricHeader(_ title: String, _ value: String, history: [Double], range: ClosedRange<Double>? = nil, color: Color) -> some View {
        HStack {
            Text(title).font(.caption.weight(.semibold)).frame(width: 58, alignment: .leading)
            Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
            Sparkline(values: history, color: color, lineWidth: 1.2, range: range).frame(width: 90, height: 16)
        }
        .accessibilityElement(children: .combine)
    }

    private func rate(_ bps: Double) -> String { ByteCountFormatter.string(fromByteCount: Int64(bps), countStyle: .file) + "/s" }
    private func pressureText(_ p: Int) -> String { p >= 4 ? "Critical" : p >= 2 ? "Warning" : "Normal" }
    private func pressureColor(_ p: Int) -> Color { p >= 4 ? .red : p >= 2 ? .orange : .green }
}
