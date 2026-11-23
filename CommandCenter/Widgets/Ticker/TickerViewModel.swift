import Foundation

@MainActor @Observable
final class TickerViewModel {
    var quotes: [String: TickerQuote] = [:]
    var failed: Set<String> = []
    var loading = false

    func refresh(_ config: TickerConfiguration) async {
        loading = true
        let symbols = config.entries.map(\.symbol).filter { !$0.isEmpty }
        let range = config.range
        await withTaskGroup(of: (String, TickerQuote?).self) { group in
            for s in symbols { group.addTask { (s, await TickerStore.quote(s, range: range)) } }
            for await (s, q) in group {
                if let q { quotes[s] = q; failed.remove(s) } else { failed.insert(s) }
            }
        }
        loading = false
        checkAlerts(config)
    }

    func portfolioValue(_ config: TickerConfiguration) -> (value: Double, dayChange: Double) {
        config.entries.reduce((0, 0)) { acc, e in
            guard let q = quotes[e.symbol], e.holdings > 0 else { return acc }
            return (acc.0 + q.price * e.holdings, acc.1 + q.change * e.holdings)
        }
    }

    private func checkAlerts(_ config: TickerConfiguration) {
        for e in config.entries {
            guard let q = quotes[e.symbol] else { continue }
            if let hi = e.alertAbove, q.price >= hi, TickerStore.shouldFire("\(e.symbol)>\(hi)") {
                Notifier.post("\(q.symbol) above \(hi.formatted())", "Now \(q.price.formatted(.number.precision(.fractionLength(2)))) \(q.currency)")
            }
            if let lo = e.alertBelow, q.price <= lo, TickerStore.shouldFire("\(e.symbol)<\(lo)") {
                Notifier.post("\(q.symbol) below \(lo.formatted())", "Now \(q.price.formatted(.number.precision(.fractionLength(2)))) \(q.currency)")
            }
        }
    }
}
