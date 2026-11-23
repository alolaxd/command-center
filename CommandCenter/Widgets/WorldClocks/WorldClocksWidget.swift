import SwiftUI

struct WorldClocksWidget: DashboardWidget {
    static let kind = "worldclocks"
    static let title = "World Clocks"
    static let symbol = "globe"
    static let summary = "Multiple time zones, contacts per city and a meeting planner showing overlapping work hours."
    static let category = WidgetCategory.utility
    static let defaultSize = GridSize(4, 3)
    static let refreshInterval: TimeInterval? = 30

    let context: WidgetContext<WorldClocksConfiguration>
    @State private var vm = WorldClocksViewModel()

    init(context: WidgetContext<WorldClocksConfiguration>) { self.context = context }

    var body: some View {
        let c = context.config
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(c.zones) { z in
                    let h = vm.hour(z, at: vm.now)
                    let working = h >= c.workStart && h < c.workEnd
                    HStack {
                        Image(systemName: h >= 6 && h < 19 ? "sun.max.fill" : "moon.fill").foregroundStyle(h >= 6 && h < 19 ? .orange : .indigo).frame(width: 18)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(z.city).font(.callout.weight(.medium))
                            Text(vm.contacts[z.identifier].map { $0.prefix(3).joined(separator: ", ") } ?? vm.offset(z))
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(vm.now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: z.tz)))
                            .font(.title3.monospacedDigit()).foregroundStyle(working ? .primary : .secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                if c.showPlanner && c.zones.count > 1 { planner(c) }
            }
        }
        .refreshing(every: Self.refreshInterval) { vm.tick() }
        .task(id: c.showContacts) { await vm.loadContacts(c) }
    }

    private func planner(_ c: WorldClocksConfiguration) -> some View {
        let ref = c.zones.first?.tz ?? .current
        let overlap = Set(WorldClocksStore.overlap(zones: c.zones, workStart: c.workStart, workEnd: c.workEnd, reference: ref))
        var cal = Calendar(identifier: .gregorian); cal.timeZone = ref
        let start = cal.startOfDay(for: vm.now)
        return VStack(alignment: .leading, spacing: 3) {
            Divider()
            Text(overlap.isEmpty ? "No shared working hours today" : "Shared working hours (in \(c.zones.first?.city ?? "")): \(ranges(overlap.sorted()))")
                .font(.caption.weight(.semibold)).foregroundStyle(overlap.isEmpty ? .orange : .green)
            ForEach(c.zones) { z in
                HStack(spacing: 1) {
                    Text(z.city).font(.system(size: 9)).frame(width: 60, alignment: .leading).lineLimit(1)
                    ForEach(0..<24, id: \.self) { h in
                        let instant = start.addingTimeInterval(Double(h) * 3600 + 1800)
                        let lh = vm.hour(z, at: instant)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(lh >= c.workStart && lh < c.workEnd ? (overlap.contains(h) ? Color.green : Color.blue.opacity(0.45)) : Color.primary.opacity(0.07))
                            .frame(height: 10)
                            .help("\(z.city): \(lh):00")
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(overlap.isEmpty ? "No overlapping work hours" : "Overlapping work hours: \(ranges(overlap.sorted()))")
    }

    private func ranges(_ hours: [Int]) -> String {
        guard let first = hours.first else { return "" }
        var out: [String] = []
        var s = first, prev = first
        for h in hours.dropFirst() { if h == prev + 1 { prev = h } else { out.append("\(s):00–\(prev + 1):00"); s = h; prev = h } }
        out.append("\(s):00–\(prev + 1):00")
        return out.joined(separator: ", ")
    }
}
