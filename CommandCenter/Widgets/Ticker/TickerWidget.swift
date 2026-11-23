import SwiftUI

struct TickerWidget: DashboardWidget {
    static let kind = "tickers"
    static let title = "Stocks & Crypto"
    static let symbol = "chart.line.uptrend.xyaxis"
    static let summary = "Watchlist with live prices and 1D/1W/1M sparklines, price alerts and a portfolio total."
    static let category = WidgetCategory.finance
    static let defaultSize = GridSize(4, 3)
    static let refreshInterval: TimeInterval? = 120

    let context: WidgetContext<TickerConfiguration>
    @State private var vm = TickerViewModel()

    init(context: WidgetContext<TickerConfiguration>) { self.context = context }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if context.config.showPortfolio {
                    let p = vm.portfolioValue(context.config)
                    if p.value > 0 {
                        StatTile(label: "Portfolio", value: p.value.usd, detail: (p.dayChange >= 0 ? "+" : "") + p.dayChange.usd,
                                 tint: .primary)
                    }
                }
                Spacer()
                Picker("", selection: Binding(get: { context.config.range }, set: { var c = context.config; c.range = $0; context.updateConfig(c) })) {
                    ForEach(TickerStore.Range.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            AddField(prompt: "Add symbol (AAPL, crypto:ethereum)") { sym in
                var c = context.config; c.entries.append(TickerEntry(symbol: sym)); context.updateConfig(c)
            }
            List(context.config.entries) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(vm.quotes[e.symbol]?.symbol ?? e.symbol.uppercased()).font(.callout.weight(.semibold))
                        if e.holdings > 0 { Text("\(e.holdings.formatted()) held").font(.caption2).foregroundStyle(.secondary) }
                    }
                    .frame(width: 90, alignment: .leading)
                    if let q = vm.quotes[e.symbol] {
                        Sparkline(values: q.series, color: q.change >= 0 ? .green : .red, lineWidth: 1.2).frame(height: 22)
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(q.price.formatted(.number.precision(.fractionLength(q.price < 10 ? 4 : 2)))).font(.callout.monospacedDigit())
                            Text((q.changePct >= 0 ? "+" : "") + q.changePct.formatted(.percent.precision(.fractionLength(2))))
                                .font(.caption.monospacedDigit()).foregroundStyle(q.change >= 0 ? .green : .red)
                        }
                        .frame(width: 84, alignment: .trailing)
                    } else if vm.failed.contains(e.symbol) {
                        Spacer(); Text("unavailable").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Spacer(); ProgressView().controlSize(.small)
                    }
                }
                .contextMenu {
                    Button("Remove", role: .destructive) { var c = context.config; c.entries.removeAll { $0.id == e.id }; context.updateConfig(c) }
                }
                .accessibilityElement(children: .combine)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
        }
        .refreshing(every: Self.refreshInterval) { await vm.refresh(context.config) }
        .onChange(of: context.config) { Task { await vm.refresh(context.config) } }
    }
}
