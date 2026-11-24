import Foundation
import GRDB
import SwiftUI

/// Owns all workspaces, the selected one, and per-workspace layouts. Saves automatically.
@MainActor @Observable
final class WorkspaceStore: MigrationProvider {
    static let shared = WorkspaceStore()

    var workspaces: [Workspace] = []
    var selectedID: UUID?
    var zenWidgetID: UUID?
    var focusedWidgetID: UUID?
    var editingWidgetID: UUID?

    @ObservationIgnored private var saveTask: Task<Void, Never>?

    nonisolated static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("workspace.v1") { db in
            try db.create(table: "workspace") { t in
                t.primaryKey("id", .text)
                t.column("position", .integer).notNull()
                t.column("json", .blob).notNull()
            }
        }
    }

    init() {
        load()
    }

    var current: Workspace? {
        get { workspaces.first { $0.id == selectedID } ?? workspaces.first }
    }

    var currentIndex: Int? { workspaces.firstIndex { $0.id == current?.id } }

    // MARK: Persistence

    private func load() {
        let rows: [Data] = AppDatabase.shared.read { db in
            try Data.fetchAll(db, sql: "SELECT json FROM workspace ORDER BY position")
        } ?? []
        workspaces = rows.compactMap { try? JSONDecoder().decode(Workspace.self, from: $0) }
        // Defaults are seeded once; after that an empty list is a valid user choice.
        if workspaces.isEmpty && !AppMeta.flag("workspaces.seeded") {
            workspaces = WorkspacePresets.defaults()
            saveNow()
        }
        AppMeta.setFlag("workspaces.seeded")
        selectedID = UserDefaults.standard.string(forKey: "selectedWorkspace").flatMap(UUID.init) ?? workspaces.first?.id
        if !workspaces.contains(where: { $0.id == selectedID }) { selectedID = workspaces.first?.id }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let snapshot = workspaces
        AppDatabase.shared.write { db in
            try db.execute(sql: "DELETE FROM workspace")
            for (i, ws) in snapshot.enumerated() {
                let data = try JSONEncoder().encode(ws)
                try db.execute(sql: "INSERT INTO workspace (id, position, json) VALUES (?, ?, ?)",
                               arguments: [ws.id.uuidString, i, data])
            }
        }
        if let selectedID { UserDefaults.standard.set(selectedID.uuidString, forKey: "selectedWorkspace") }
    }

    // MARK: Workspace operations

    func select(_ id: UUID) {
        zenWidgetID = nil
        selectedID = id
        UserDefaults.standard.set(id.uuidString, forKey: "selectedWorkspace")
    }

    func select(index: Int) {
        guard workspaces.indices.contains(index) else { return }
        select(workspaces[index].id)
    }

    func select(named name: String) -> Bool {
        guard let ws = workspaces.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        select(ws.id); return true
    }

    func selectNext(_ delta: Int) {
        guard let i = currentIndex, !workspaces.isEmpty else { return }
        select(index: (i + delta + workspaces.count) % workspaces.count)
    }

    func addWorkspace(name: String, symbol: String = "square.grid.2x2") {
        let ws = Workspace(name: name, symbol: symbol)
        workspaces.append(ws)
        select(ws.id)
        scheduleSave()
    }

    func renameWorkspace(_ id: UUID, to name: String) {
        mutate(id) { $0.name = name }
    }

    func deleteWorkspace(_ id: UUID) {
        guard let idx = workspaces.firstIndex(where: { $0.id == id }) else { return }
        // Shut down terminals owned by this workspace's terminal widgets.
        for inst in workspaces[idx].widgets where inst.kind == TerminalPanesWidget.kind {
            let cfg = TerminalPanesWidget.decodeConfig(inst.config)
            cfg.tabs.flatMap(\.panes).forEach { TerminalPanesStore.close($0, instance: inst.id) }
        }
        workspaces.remove(at: idx)
        if selectedID == id {
            selectedID = workspaces.isEmpty ? nil : workspaces[min(idx, workspaces.count - 1)].id
            zenWidgetID = nil
        }
        saveNow()
    }

    func moveWorkspace(from: IndexSet, to: Int) {
        workspaces.move(fromOffsets: from, toOffset: to)
        scheduleSave()
    }

    private func mutate(_ id: UUID?, _ change: (inout Workspace) -> Void) {
        guard let id, let i = workspaces.firstIndex(where: { $0.id == id }) else { return }
        change(&workspaces[i])
        scheduleSave()
    }

    private func mutateCurrent(_ change: (inout Workspace) -> Void) { mutate(current?.id, change) }

    // MARK: Widget operations

    func gridItems(_ ws: Workspace) -> [LayoutItem] {
        ws.widgets.filter { !$0.isHidden }.map {
            LayoutItem(id: $0.id, rect: $0.frame, minSize: WidgetRegistry.descriptor($0.kind)?.minSize ?? GridSize(1, 1))
        }
    }

    @discardableResult
    func addWidget(kind: String) -> UUID? {
        guard let d = WidgetRegistry.descriptor(kind), let ws = current else { return nil }
        let rect = GridLayoutEngine.firstFreeSlot(for: d.defaultSize, in: gridItems(ws), columns: ws.columns)
        let inst = WidgetInstance(kind: kind, frame: rect, config: d.defaultConfig)
        mutateCurrent { $0.widgets.append(inst) }
        focusedWidgetID = inst.id
        return inst.id
    }

    func removeWidget(_ id: UUID) {
        mutateCurrent { ws in ws.widgets.removeAll { $0.id == id } }
        if zenWidgetID == id { zenWidgetID = nil }
    }

    func toggleHidden(_ id: UUID) {
        mutateCurrent { ws in
            guard let i = ws.widgets.firstIndex(where: { $0.id == id }) else { return }
            ws.widgets[i].isHidden.toggle()
            if !ws.widgets[i].isHidden {
                let others = gridItems(ws).filter { $0.id != id }
                ws.widgets[i].frame = GridLayoutEngine.firstFreeSlot(for: ws.widgets[i].frame.size, in: others, columns: ws.columns)
            }
        }
    }

    func updateConfig(_ id: UUID, _ data: Data) {
        mutateCurrent { ws in
            guard let i = ws.widgets.firstIndex(where: { $0.id == id }), ws.widgets[i].config != data else { return }
            ws.widgets[i].config = data
        }
    }

    /// Commits a layout computed by the engine.
    func commit(_ items: [LayoutItem]) {
        mutateCurrent { apply(items, to: &$0) }
    }

    func preview(placing id: UUID, at rect: GridRect) -> [LayoutItem] {
        guard let ws = current else { return [] }
        return GridLayoutEngine.place(gridItems(ws), id: id, at: rect, columns: ws.columns)
    }

    func nudge(_ id: UUID, dx: Int = 0, dy: Int = 0, dw: Int = 0, dh: Int = 0) {
        guard let ws = current, let inst = ws.widgets.first(where: { $0.id == id }) else { return }
        var r = inst.frame
        r.x += dx; r.y += dy; r.w += dw; r.h += dh
        commit(preview(placing: id, at: r))
    }

    /// Explicit "Tidy Up": floats every widget up to close gaps.
    func tidyUp() {
        mutateCurrent { ws in apply(GridLayoutEngine.compact(gridItems(ws)), to: &ws) }
    }

    func setColumns(_ n: Int) {
        mutateCurrent { ws in
            ws.columns = n
            apply(GridLayoutEngine.compact(gridItems(ws).map { item in
                var i = item; i.rect = GridLayoutEngine.clamp(item.rect, minSize: item.minSize, columns: n); return i
            }), to: &ws)
        }
    }

    private func apply(_ items: [LayoutItem], to ws: inout Workspace) {
        let map = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.rect) })
        for i in ws.widgets.indices { if let r = map[ws.widgets[i].id] { ws.widgets[i].frame = r } }
    }

    // MARK: Zen

    func toggleZen() {
        if zenWidgetID != nil { zenWidgetID = nil; return }
        zenWidgetID = focusedWidgetID ?? current?.widgets.first(where: { !$0.isHidden })?.id
    }

    func focusFirst(kind: String) -> UUID? {
        if let id = current?.widgets.first(where: { $0.kind == kind && !$0.isHidden })?.id { focusedWidgetID = id; return id }
        for ws in workspaces {
            if let inst = ws.widgets.first(where: { $0.kind == kind && !$0.isHidden }) {
                select(ws.id); focusedWidgetID = inst.id; return inst.id
            }
        }
        return nil
    }

    // MARK: Import / export

    func exportJSON() throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(LayoutExport(workspaces: workspaces))
    }

    func importJSON(_ data: Data, replace: Bool) throws {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let export = try dec.decode(LayoutExport.self, from: data)
        let imported = export.workspaces.map { ws -> Workspace in
            var w = ws; w.id = UUID()
            w.widgets = ws.widgets.filter { WidgetRegistry.descriptor($0.kind) != nil }.map { var i = $0; i.id = UUID(); return i }
            return w
        }
        if replace { workspaces = imported } else { workspaces.append(contentsOf: imported) }
        selectedID = imported.first?.id ?? workspaces.first?.id
        saveNow()
    }

    func applyPreset(_ preset: Workspace) {
        var ws = preset; ws.id = UUID()
        workspaces.append(ws)
        select(ws.id)
        scheduleSave()
    }
}
