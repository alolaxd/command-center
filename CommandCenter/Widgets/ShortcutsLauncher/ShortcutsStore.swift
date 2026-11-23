import AppKit
import Foundation
import GRDB

struct LauncherItem: Codable, Identifiable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "launcher_item"
    enum Kind: String, Codable, CaseIterable, DatabaseValueConvertible {
        case shortcut = "Shortcut", shell = "Shell Script", applescript = "AppleScript", url = "URL", app = "App"
    }
    var id: String = UUID().uuidString
    var kind: Kind
    var label: String
    var value: String
    var symbol: String = "bolt.fill"
    var color: String = "blue"
    var position: Double = 0
}

@MainActor
enum ShortcutsStore: MigrationProvider {
    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("launcher.v1") { db in
            try db.create(table: "launcher_item") { t in
                t.primaryKey("id", .text)
                t.column("kind", .text).notNull()
                t.column("label", .text).notNull()
                t.column("value", .text).notNull()
                t.column("symbol", .text).notNull()
                t.column("color", .text).notNull()
                t.column("position", .double).notNull()
            }
            try LauncherItem(kind: .url, label: "GitHub", value: "https://github.com", symbol: "chevron.left.forwardslash.chevron.right", color: "gray", position: 0).insert(db)
            try LauncherItem(kind: .shell, label: "Flush DNS", value: "dscacheutil -flushcache && echo done", symbol: "network", color: "teal", position: 1).insert(db)
            try LauncherItem(kind: .applescript, label: "Dark Mode", value: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode", symbol: "circle.lefthalf.filled", color: "purple", position: 2).insert(db)
        }
    }

    static func all() -> [LauncherItem] { AppDatabase.shared.read { try LauncherItem.order(Column("position")).fetchAll($0) } ?? [] }
    static func save(_ i: LauncherItem) { AppDatabase.shared.write { try i.save($0) } }
    static func delete(_ i: LauncherItem) { AppDatabase.shared.write { _ = try i.delete($0) } }

    static func reorder(_ ids: [String]) {
        AppDatabase.shared.write { db in for (i, id) in ids.enumerated() { try db.execute(sql: "UPDATE launcher_item SET position = ? WHERE id = ?", arguments: [i, id]) } }
    }

    /// Names of the user's macOS Shortcuts.
    static func systemShortcuts() async -> [String] {
        let r = await Shell.run("/usr/bin/shortcuts", ["list"], timeout: 15)
        return r.stdout.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }

    /// Runs an item; returns output or an error message.
    static func run(_ i: LauncherItem) async -> (ok: Bool, output: String) {
        switch i.kind {
        case .shortcut:
            let r = await Shell.run("/usr/bin/shortcuts", ["run", i.value], timeout: 300)
            return (r.ok, (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        case .shell:
            let r = await Shell.runLine(i.value)
            return (r.ok, (r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        case .applescript:
            let (out, err) = await AppleScriptRunner.run(i.value)
            return (err == nil, err ?? out ?? "")
        case .url:
            guard let url = URL(string: i.value) else { return (false, "Invalid URL") }
            return (NSWorkspace.shared.open(url), "")
        case .app:
            let url = URL(fileURLWithPath: i.value)
            do { try await NSWorkspace.shared.openApplication(at: url, configuration: .init()); return (true, "") }
            catch { return (false, error.localizedDescription) }
        }
    }
}
