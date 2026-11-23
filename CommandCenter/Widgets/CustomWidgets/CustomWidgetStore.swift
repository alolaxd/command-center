import Foundation
import GRDB
import JavaScriptCore

struct CustomWidgetDef: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "custom_widget"
    var id: String = UUID().uuidString
    var name: String
    var author: String = ""
    var script: String
    var updatedAt = Date()
}

/// `.ccwidget` bundle format (JSON).
struct CCWidgetBundle: Codable {
    var format = "ccwidget/1"
    var name: String
    var author: String
    var script: String
}

/// Declarative node tree returned by a widget's `render()` function.
indirect enum JSNode: Hashable {
    case text(String, style: String)
    case stat(label: String, value: String)
    case progress(Double, label: String?)
    case sparkline([Double])
    case list([String])
    case symbol(String)
    case stack(horizontal: Bool, children: [JSNode])
    case spacer

    static func parse(_ v: Any?) -> JSNode? {
        if let s = v as? String { return .text(s, style: "body") }
        if let n = v as? NSNumber { return .text(n.stringValue, style: "body") }
        guard let o = v as? [String: Any], let type = o["type"] as? String else { return nil }
        switch type {
        case "text": return .text("\(o["value"] ?? "")", style: o["style"] as? String ?? "body")
        case "stat": return .stat(label: "\(o["label"] ?? "")", value: "\(o["value"] ?? "")")
        case "progress": return .progress((o["value"] as? NSNumber)?.doubleValue ?? 0, label: o["label"] as? String)
        case "sparkline": return .sparkline((o["values"] as? [NSNumber])?.map(\.doubleValue) ?? [])
        case "list": return .list((o["items"] as? [Any])?.map { "\($0)" } ?? [])
        case "symbol": return .symbol(o["name"] as? String ?? "questionmark")
        case "spacer": return .spacer
        case "hstack", "vstack": return .stack(horizontal: type == "hstack", children: (o["children"] as? [Any])?.compactMap(parse) ?? [])
        default: return .text("Unknown node: \(type)", style: "caption")
        }
    }
}

@MainActor
enum CustomWidgetStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("customwidget.v1") { db in
            try db.create(table: "custom_widget") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("author", .text).notNull()
                t.column("script", .text).notNull()
                t.column("updatedAt", .datetime).notNull()
            }
        }
    }

    static func all() -> [CustomWidgetDef] { AppDatabase.shared.read { try CustomWidgetDef.order(Column("name")).fetchAll($0) } ?? [] }
    static func get(_ id: String) -> CustomWidgetDef? { (AppDatabase.shared.read { try CustomWidgetDef.fetchOne($0, key: id) }) ?? nil }
    static func save(_ d: CustomWidgetDef) { var x = d; x.updatedAt = Date(); AppDatabase.shared.write { try x.save($0) } }
    static func delete(_ d: CustomWidgetDef) { AppDatabase.shared.write { _ = try d.delete($0) } }

    static func export(_ d: CustomWidgetDef, to url: URL) throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(CCWidgetBundle(name: d.name, author: d.author, script: d.script)).write(to: url)
    }

    static func importBundle(_ url: URL) throws -> CustomWidgetDef {
        let b = try JSONDecoder().decode(CCWidgetBundle.self, from: Data(contentsOf: url))
        guard b.format.hasPrefix("ccwidget/") else { throw CocoaError(.fileReadCorruptFile) }
        let d = CustomWidgetDef(name: b.name, author: b.author, script: b.script)
        save(d)
        return d
    }

    // MARK: Runtime

    /// Runs `render()` in a fresh, sandboxed JSContext (no network or file access) with the `cc` API.
    static func render(_ script: String, widgetID: String) -> Result<JSNode, CustomWidgetError> {
        guard let ctx = JSContext() else { return .failure(.message("JavaScriptCore unavailable")) }
        var exceptionText: String?
        ctx.exceptionHandler = { _, exc in exceptionText = exc?.toString() }
        installAPI(ctx, widgetID: widgetID)
        ctx.evaluateScript(script)
        if let e = exceptionText { return .failure(.message(e)) }
        guard let fn = ctx.objectForKeyedSubscript("render"), !fn.isUndefined else { return .failure(.message("Define a function named render()")) }
        let value = fn.call(withArguments: [])
        if let e = exceptionText { return .failure(.message(e)) }
        guard let node = JSNode.parse(value?.toObject()) else { return .failure(.message("render() must return a node, e.g. {type: \"text\", value: \"Hi\"}")) }
        return .success(node)
    }

    private static func installAPI(_ ctx: JSContext, widgetID: String) {
        let cc = JSValue(newObjectIn: ctx)!
        let now: @convention(block) () -> Double = { Date().timeIntervalSince1970 * 1000 }
        cc.setObject(now, forKeyedSubscript: "now" as NSString)
        let storeKey = "customwidget.\(widgetID)."
        let get: @convention(block) (String) -> Any? = { UserDefaults.standard.object(forKey: storeKey + $0) }
        let set: @convention(block) (String, Any?) -> Void = { UserDefaults.standard.set($1, forKey: storeKey + $0) }
        let storage = JSValue(newObjectIn: ctx)!
        storage.setObject(get, forKeyedSubscript: "get" as NSString)
        storage.setObject(set, forKeyedSubscript: "set" as NSString)
        cc.setObject(storage, forKeyedSubscript: "storage" as NSString)

        // Read-only access to dashboard data.
        let data = JSValue(newObjectIn: ctx)!
        let pomodoros: @convention(block) () -> Int = { MainActor.assumeIsolated { PomodoroStore.countToday() } }
        let habits: @convention(block) () -> [[String: Any]] = {
            MainActor.assumeIsolated {
                HabitStore.habits().map { h in
                    let (cur, best) = HabitStore.streaks(HabitStore.allDays(h.id))
                    return ["name": h.name, "streak": cur, "best": best, "doneToday": HabitStore.allDays(h.id).contains(Date().dayKey)]
                }
            }
        }
        let inbox: @convention(block) () -> Int = { MainActor.assumeIsolated { InboxStore.untriaged().count } }
        let spent: @convention(block) () -> Double = { MainActor.assumeIsolated { BudgetStore.spentByCategory(Date()).values.reduce(0, +) } }
        let agentCost: @convention(block) () -> Double = {
            MainActor.assumeIsolated { AgentMonitorStore.costs(since: Calendar.current.startOfDay(for: Date())).map(\.cost).reduce(0, +) }
        }
        data.setObject(pomodoros, forKeyedSubscript: "pomodorosToday" as NSString)
        data.setObject(habits, forKeyedSubscript: "habits" as NSString)
        data.setObject(inbox, forKeyedSubscript: "inboxCount" as NSString)
        data.setObject(spent, forKeyedSubscript: "spentThisMonth" as NSString)
        data.setObject(agentCost, forKeyedSubscript: "agentCostToday" as NSString)
        cc.setObject(data, forKeyedSubscript: "data" as NSString)
        ctx.setObject(cc, forKeyedSubscript: "cc" as NSString)
    }

    static let samples: [(String, String)] = [
        ("Weekend Countdown", """
        function render() {
          const d = new Date(cc.now());
          const daysLeft = (6 - d.getDay() + 7) % 7;
          return { type: "vstack", children: [
            { type: "text", value: daysLeft === 0 ? "It's the weekend 🎉" : daysLeft + " days to the weekend", style: "title" },
            { type: "progress", value: (5 - Math.min(5, daysLeft)) / 5, label: "Week progress" }
          ]};
        }
        """),
        ("Focus Score", """
        function render() {
          const p = cc.data.pomodorosToday();
          const goal = 8;
          return { type: "hstack", children: [
            { type: "symbol", name: "timer" },
            { type: "stat", label: "Pomodoros today", value: p + " / " + goal },
            { type: "progress", value: p / goal }
          ]};
        }
        """),
        ("Habit Streaks", """
        function render() {
          const habits = cc.data.habits();
          return { type: "vstack", children: [
            { type: "text", value: "Streaks", style: "headline" },
            { type: "list", items: habits.map(h => (h.doneToday ? "✅ " : "⬜️ ") + h.name + " — " + h.streak + " days (best " + h.best + ")") }
          ]};
        }
        """),
        ("Click Counter", """
        function render() {
          const n = (cc.storage.get("renders") || 0) + 1;
          cc.storage.set("renders", n);
          const history = (cc.storage.get("history") || []).concat([n % 7]).slice(-20);
          cc.storage.set("history", history);
          return { type: "vstack", children: [
            { type: "stat", label: "Refreshes", value: String(n) },
            { type: "sparkline", values: history }
          ]};
        }
        """),
    ]
}

enum CustomWidgetError: Error, Equatable { case message(String) }
