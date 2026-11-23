import Charts
import SwiftUI

struct ScreenTimeWidget: DashboardWidget {
    static let kind = "screentime"
    static let title = "Screen Time"
    static let symbol = "hourglass.bottomhalf.filled"
    static let summary = "Today's screen time, top apps by usage, pickups and a 7-day trend (tracked on this Mac)."
    static let category = WidgetCategory.utility
    static let defaultSize = GridSize(4, 3)
    static let refreshInterval: TimeInterval? = 60

    let context: WidgetContext<ScreenTimeConfiguration>
    @State private var vm = ScreenTimeViewModel()

    init(context: WidgetContext<ScreenTimeConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                StatTile(label: "Today", value: vm.total.compactDuration)
                StatTile(label: "Pickups", value: "\(vm.pickups)")
                Chart(vm.week, id: \.0) { d in
                    BarMark(x: .value("Day", String(d.0.suffix(2))), y: .value("Hours", d.1 / 3600))
                        .foregroundStyle(d.0 == Date().dayKey ? Color.accentColor : Color.secondary.opacity(0.4))
                }
                .chartYAxis(.hidden)
                .frame(width: 130, height: 44)
                .accessibilityLabel("Screen time over the last 7 days")
            }
            let maxSecs = vm.usage.first?.seconds ?? 1
            ForEach(vm.usage.prefix(context.config.topCount)) { u in
                HStack(spacing: 6) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: u.bundleId) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                    }
                    Text(u.name).font(.caption).frame(width: 100, alignment: .leading).lineLimit(1)
                    MeterBar(fraction: u.seconds / maxSecs, height: 6)
                    Text(u.seconds.compactDuration).font(.caption.monospacedDigit()).frame(width: 58, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
            if vm.usage.isEmpty { EmptyStateView(symbol: "hourglass", title: "Tracking started", message: "Usage appears as you switch apps.") }
        }
        .refreshing(every: Self.refreshInterval) { vm.load() }
    }
}
