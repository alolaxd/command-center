import Foundation

/// Estimated list prices (USD per million tokens). Used only for local cost estimates.
enum AgentPricing {
    struct Price { let input: Double; let output: Double; let cacheRead: Double? }

    static let table: [(prefix: String, price: Price)] = [
        ("claude-fable-5-2", Price(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-mythos-5-2", Price(input: 8, output: 40, cacheRead: 0.20)),
        ("claude-fable-5", Price(input: 10, output: 50, cacheRead: nil)),
        ("claude-mythos-5", Price(input: 10, output: 50, cacheRead: nil)),
        ("claude-opus-5-5", Price(input: 4, output: 20, cacheRead: 0.20)),
        ("claude-opus-5", Price(input: 5, output: 25, cacheRead: nil)),
        ("claude-opus-4-8", Price(input: 5, output: 25, cacheRead: nil)),
        ("claude-opus-4-7", Price(input: 5, output: 25, cacheRead: nil)),
        ("claude-opus-4-6", Price(input: 5, output: 25, cacheRead: nil)),
        ("claude-opus-4-5", Price(input: 5, output: 25, cacheRead: nil)),
        ("claude-opus-4", Price(input: 15, output: 75, cacheRead: nil)),
        ("claude-sonnet-5-5", Price(input: 2, output: 10, cacheRead: 0.10)),
        ("claude-sonnet-5", Price(input: 2, output: 10, cacheRead: nil)),
        ("claude-sonnet-4", Price(input: 3, output: 15, cacheRead: nil)),
        ("claude-3-7-sonnet", Price(input: 3, output: 15, cacheRead: nil)),
        ("claude-haiku-5-5", Price(input: 0.10, output: 0.50, cacheRead: nil)),
        ("claude-haiku-4-5", Price(input: 1, output: 5, cacheRead: nil)),
        ("claude-3-5-haiku", Price(input: 0.8, output: 4, cacheRead: nil)),
        ("gpt-5", Price(input: 1.25, output: 10, cacheRead: 0.125)),
        ("gpt-4.1", Price(input: 2, output: 8, cacheRead: 0.5)),
        ("gpt-4o", Price(input: 2.5, output: 10, cacheRead: 1.25)),
        ("o3", Price(input: 2, output: 8, cacheRead: 0.5)),
        ("o4-mini", Price(input: 1.1, output: 4.4, cacheRead: 0.275)),
    ]

    static func price(for model: String) -> Price? {
        let m = model.lowercased()
        return table.first { m.contains($0.prefix) }?.price
    }

    /// Anthropic-style usage: cache writes cost 1.25× (5 min) or 2× (1 h) input; reads ~0.1× unless listed.
    static func cost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int) -> Double {
        guard let p = price(for: model) else { return 0 }
        let read = p.cacheRead ?? p.input * 0.1
        return (Double(input) * p.input + Double(output) * p.output + Double(cacheRead) * read
                + Double(cacheWrite5m) * p.input * 1.25 + Double(cacheWrite1h) * p.input * 2) / 1_000_000
    }
}
