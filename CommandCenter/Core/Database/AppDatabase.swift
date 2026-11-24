import Foundation
import GRDB

/// Anything that owns tables registers its migrations here.
protocol MigrationProvider {
    static func registerMigrations(_ migrator: inout DatabaseMigrator)
}

/// Local-first storage: one SQLite database in Application Support plus file-based notes/attachments.
final class AppDatabase {
    static let shared: AppDatabase = {
        do { return try AppDatabase(path: AppPaths.database.path) }
        catch { fatalError("Could not open database: \(error)") }
    }()

    let pool: DatabasePool

    init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        pool = try DatabasePool(path: path, configuration: config)
        var migrator = DatabaseMigrator()
        for provider in AppDatabase.providers { provider.registerMigrations(&migrator) }
        try migrator.migrate(pool)
    }

    /// Order matters only for new installs; each provider uses unique migration identifiers.
    static let providers: [MigrationProvider.Type] = [
        WorkspaceStore.self, InboxStore.self, NotesStore.self, KanbanStore.self, PomodoroStore.self,
        HabitStore.self, JournalStore.self, AgentMonitorStore.self, SnippetStore.self, APIHealthStore.self,
        BatteryStore.self, RemindersStore.self, AIChatStore.self, NewsStore.self, BookmarksStore.self,
        TickerStore.self, BudgetStore.self, HealthStore.self, MusicStore.self, CountdownStore.self,
        ScreenTimeStore.self, ShortcutsStore.self, CustomWidgetStore.self, AppMeta.self,
    ]

    func read<T>(_ block: (Database) throws -> T) -> T? {
        do { return try pool.read(block) } catch { print("DB read error: \(error)"); return nil }
    }

    @discardableResult
    func write<T>(_ block: (Database) throws -> T) -> T? {
        do { return try pool.write(block) } catch { print("DB write error: \(error)"); return nil }
    }
}

enum AppPaths {
    static var isRunningTests: Bool { ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    /// Demo mode (CC_DEMO=1 or set by the screenshot generator): never reads the user's agent logs,
    /// processes or shell config, so captures contain only sample data.
    nonisolated(unsafe) static var demoMode = ProcessInfo.processInfo.environment["CC_DEMO"] != nil

    /// Tests (and power users) can redirect storage with CC_DATA_DIR.
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = ProcessInfo.processInfo.environment["CC_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? base.appendingPathComponent("CommandCenter", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    static var database: URL { root.appendingPathComponent("commandcenter.sqlite") }
    static func folder(_ name: String) -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var notes: URL { folder("Notes") }
    static var attachments: URL { folder("Attachments") }
    static var customWidgets: URL { folder("Widgets") }
}

extension Date {
    /// yyyy-MM-dd in the current calendar, used as a day key across stores.
    var dayKey: String { DayKey.formatter.string(from: self) }
    static func fromDayKey(_ key: String) -> Date? { DayKey.formatter.date(from: key) }
}

enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

/// Small key/value table for flags that must travel with the database (e.g. "defaults seeded").
enum AppMeta: MigrationProvider {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("meta.v1") { db in
            try db.create(table: "app_meta") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }
            // Existing databases already had their defaults seeded.
            if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM workspace") ?? 0 > 0 {
                try db.execute(sql: "INSERT INTO app_meta (key, value) VALUES ('workspaces.seeded', '1')")
            }
            if try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM habit") ?? 0 > 0 {
                try db.execute(sql: "INSERT INTO app_meta (key, value) VALUES ('habits.seeded', '1')")
            }
        }
    }

    static func flag(_ key: String) -> Bool {
        (AppDatabase.shared.read { try String.fetchOne($0, sql: "SELECT value FROM app_meta WHERE key = ?", arguments: [key]) } ?? nil) == "1"
    }

    static func setFlag(_ key: String) {
        AppDatabase.shared.write { try $0.execute(sql: "INSERT OR REPLACE INTO app_meta (key, value) VALUES (?, '1')", arguments: [key]) }
    }
}
