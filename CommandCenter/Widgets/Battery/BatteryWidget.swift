import Charts
import SwiftUI

struct BatteryWidget: DashboardWidget {
    static let kind = "battery"
    static let title = "Battery & Power"
    static let symbol = "battery.75percent"
    static let summary = "Charge, time remaining, cycle count, health, temperature, power source and charge history."
    static let category = WidgetCategory.system
    static let defaultSize = GridSize(3, 3)
    static let refreshInterval: TimeInterval? = 30

    let context: WidgetContext<BatteryConfiguration>
    @State private var vm = BatteryViewModel()

    init(context: WidgetContext<BatteryConfiguration>) { self.context = context }

    var body: some View {
        let b = vm.info
        VStack(alignment: .leading, spacing: 8) {
            if !b.present {
                EmptyStateView(symbol: "powerplug", title: "No battery", message: "This Mac runs on AC power.")
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: symbol(b)).font(.title2).foregroundStyle(b.percent <= 20 && !b.onAC ? .red : .primary)
                    Text("\(b.percent)%").font(.largeTitle.monospacedDigit().weight(.semibold))
                    VStack(alignment: .leading) {
                        Text(b.isCharging ? "Charging" : b.onAC ? "On power adapter" : "On battery").font(.caption)
                        if let t = b.timeRemaining {
                            Text("\(b.isCharging ? "Full in" : "") \(t / 60)h \(t % 60)m\(b.isCharging ? "" : " left")").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
                HStack {
                    StatTile(label: "Health", value: b.health.map { $0.percent } ?? "—", detail: b.condition)
                    StatTile(label: "Cycles", value: b.cycleCount.map(String.init) ?? "—")
                    StatTile(label: "Temp", value: b.temperature.map { String(format: "%.1f°C", $0) } ?? "—")
                    if let w = b.adapterWatts { StatTile(label: "Adapter", value: "\(w) W") }
                }
                Chart(vm.history, id: \.timestamp) { s in
                    LineMark(x: .value("Time", s.timestamp), y: .value("%", s.percent)).foregroundStyle(.green)
                    if s.charging {
                        PointMark(x: .value("Time", s.timestamp), y: .value("%", s.percent)).symbolSize(6).foregroundStyle(.yellow)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks(position: .trailing, values: [0, 50, 100]) }
                .frame(minHeight: 50)
                .overlay { if vm.history.count < 2 { Text("Charge history builds up every 5 minutes").font(.caption2).foregroundStyle(.secondary) } }
            }
        }
        .refreshing(every: Self.refreshInterval) { vm.refresh(context.config) }
    }

    private func symbol(_ b: BatteryInfo) -> String {
        if b.isCharging { return "battery.100percent.bolt" }
        switch b.percent { case 88...: return "battery.100percent"; case 63...: return "battery.75percent"; case 38...: return "battery.50percent"; case 13...: return "battery.25percent"; default: return "battery.0percent" }
    }
}
