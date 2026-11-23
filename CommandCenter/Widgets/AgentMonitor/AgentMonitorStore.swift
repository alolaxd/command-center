import Foundation
import GRDB

enum AgentProvider: String, Codable, CaseIterable, DatabaseValueConvertible, Identifiable {
    case claudeCode = "Claude Code", openCode = "OpenCode", codex = "Codex", aider = "Aider", cursor = "Cursor", windsurf = "Windsurf", custom = "Custom"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .claudeCode: "sparkle"
        case .openCode: "chevron.left.forwardslash.chevron.right"
        case .codex: "terminal"
        case .aider: "bubble.left.and.text.bubble.right"
        case .cursor, .windsurf: "cursorarrow.rays"
        case .custom: "gearshape.2"
        }
    }
}

struct AgentSession: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_session"
    var id: String
    var provider: AgentProvider
    var title: String
    var cwd: String
    var model: String
    var startedAt: Date
    var lastActivity: Date
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheTokens: Int = 0
    var cost: Double = 0
    var lastEvent: String = ""

    var totalTokens: Int { inputTokens + outputTokens + cacheTokens }
    var duration: TimeInterval { lastActivity.timeIntervalSince(startedAt) }
}

struct AgentUsage: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "agent_usage"
    var sessionId: String
    var provider: AgentProvider
    var day: String
    var cost: Double
    var tokens: Int
}

@MainActor
enum AgentMonitorStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("agents.v1") { db in
            try db.create(table: "agent_session") { t in
                t.primaryKey("id", .text)
                t.column("provider", .text).notNull()
                t.column("title", .text).notNull()
                t.column("cwd", .text).notNull()
                t.column("model", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("lastActivity", .datetime).notNull().indexed()
                t.column("inputTokens", .integer).notNull()
                t.column("outputTokens", .integer).notNull()
                t.column("cacheTokens", .integer).notNull()
                t.column("cost", .double).notNull()
                t.column("lastEvent", .text).notNull()
            }
            try db.create(table: "agent_usage") { t in
                t.column("sessionId", .text).notNull()
                t.column("provider", .text).notNull()
                t.column("day", .text).notNull().indexed()
                t.column("cost", .double).notNull()
                t.column("tokens", .integer).notNull()
                t.primaryKey(["sessionId", "day"])
            }
            try db.create(table: "agent_scan") { t in
                t.primaryKey("path", .text)
                t.column("offset", .integer).notNull()
                t.column("state", .text)
            }
        }
    }

    static func sessions(limit: Int = 200, query: String = "") -> [AgentSession] {
        AppDatabase.shared.read { db in
            var req = AgentSession.order(Column("lastActivity").desc).limit(limit)
            if !query.isEmpty {
                let p = "%\(query)%"
                req = req.filter(Column("title").like(p) || Column("cwd").like(p) || Column("model").like(p))
            }
            return try req.fetchAll(db)
        } ?? []
    }

    struct CostRow: Identifiable { let id = UUID(); let provider: AgentProvider; let cost: Double; let tokens: Int }

    static func costs(since: Date?) -> [CostRow] {
        AppDatabase.shared.read { db in
            let where_ = since.map { "WHERE day >= '\($0.dayKey)'" } ?? ""
            return try Row.fetchAll(db, sql: "SELECT provider, SUM(cost) AS c, SUM(tokens) AS t FROM agent_usage \(where_) GROUP BY provider ORDER BY c DESC")
                .compactMap { row in
                    guard let p = AgentProvider(rawValue: row["provider"]) else { return nil }
                    return CostRow(provider: p, cost: row["c"] ?? 0, tokens: row["t"] ?? 0)
                }
        } ?? []
    }

    static func aiSummary() -> String {
        func total(_ d: Date?) -> Double { costs(since: d).map(\.cost).reduce(0, +) }
        let today = Calendar.current.startOfDay(for: Date())
        let week = today.addingTimeInterval(-6 * 86400)
        let recent = sessions(limit: 10).map { "- [\($0.provider.rawValue)] \($0.title) (\($0.model), \($0.cost.usd), \($0.lastActivity.formatted(.relative(presentation: .named))))" }
        return "AI coding agents — estimated cost today \(total(today).usd), last 7 days \(total(week).usd), all time \(total(nil).usd).\nRecent sessions:\n" + recent.joined(separator: "\n")
    }
}
