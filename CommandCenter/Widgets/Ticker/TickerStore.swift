import Foundation
import GRDB

struct TickerQuote: Sendable, Equatable {
    let symbol: String
    let price: Double
    let previousClose: Double
    let currency: String
    let series: [Double]
    var change: Double { price - previousClose }
    var changePct: Double { previousClose > 0 ? change / previousClose : 0 }
}

struct TickerAlertLog: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "ticker_alert_log"
    var key: String
    var firedAt: Date
}

/// Yahoo Finance chart API for stocks/ETFs; CoinGecko for crypto (symbols prefixed "crypto:").
@MainActor
enum TickerStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("ticker.v1") { db in
            try db.create(table: "ticker_alert_log") { t in
                t.primaryKey("key", .text)
                t.column("firedAt", .datetime).notNull()
            }
        }
    }

    enum Range: String, Codable, CaseIterable { case day = "1D", week = "1W", month = "1M" }

    nonisolated static func quote(_ symbol: String, range: Range) async -> TickerQuote? {
        if symbol.lowercased().hasPrefix("crypto:") { return await crypto(String(symbol.dropFirst(7)), range: range) }
        let (r, i) = switch range { case .day: ("1d", "5m"); case .week: ("5d", "30m"); case .month: ("1mo", "1d") }
        guard let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?range=\(r)&interval=\(i)") else { return nil }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = ((obj["chart"] as? [String: Any])?["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let price = meta["regularMarketPrice"] as? Double else { return nil }
        let closes = (((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first?["close"] as? [Double?])?.compactMap { $0 } ?? []
        let prev = range == .day ? (meta["chartPreviousClose"] as? Double ?? meta["previousClose"] as? Double ?? closes.first ?? price) : (closes.first ?? price)
        return TickerQuote(symbol: symbol.uppercased(), price: price, previousClose: prev, currency: meta["currency"] as? String ?? "USD", series: closes)
    }

    nonisolated static func crypto(_ id: String, range: Range) async -> TickerQuote? {
        let days = switch range { case .day: "1"; case .week: "7"; case .month: "30" }
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(id.lowercased())/market_chart?vs_currency=usd&days=\(days)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let prices = obj["prices"] as? [[Double]], let last = prices.last?.last, let first = prices.first?.last else { return nil }
        return TickerQuote(symbol: id.uppercased(), price: last, previousClose: first, currency: "USD", series: prices.compactMap { $0.last })
    }

    /// Fires each threshold alert once per day.
    static func shouldFire(_ key: String) -> Bool {
        let fullKey = key + "|" + Date().dayKey
        let exists = AppDatabase.shared.read { try TickerAlertLog.fetchOne($0, key: fullKey) } ?? nil
        if exists != nil { return false }
        AppDatabase.shared.write { try TickerAlertLog(key: fullKey, firedAt: Date()).insert($0) }
        return true
    }
}
