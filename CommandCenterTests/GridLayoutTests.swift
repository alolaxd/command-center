import XCTest
@testable import Command_Center

final class GridLayoutTests: XCTestCase {
    let cellW: CGFloat = 100, rowH: CGFloat = 84, gap: CGFloat = 10

    private func item(_ x: Int, _ y: Int, _ w: Int, _ h: Int, min: GridSize = GridSize(1, 1)) -> LayoutItem {
        LayoutItem(id: UUID(), rect: GridRect(x: x, y: y, w: w, h: h), minSize: min)
    }

    private func pt(cells dx: Double, rows dy: Double) -> CGSize {
        CGSize(width: dx * Double(cellW + gap), height: dy * Double(rowH + gap))
    }

    /// Widgets that don't collide with the target must not move at all.
    private func assertOnlyCollidersMoved(_ s: GridDragSession, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(GridLayoutEngine.hasOverlaps(s.preview), "overlap in preview", file: file, line: line)
        for base in s.baseline where base.id != s.id {
            let now = s.rect(for: base.id)!
            if now != base.rect {
                XCTAssertGreaterThan(now.y, base.rect.y, "widgets may only be pushed down", file: file, line: line)
                XCTAssertEqual(now.x, base.rect.x, "pushed widgets keep their column", file: file, line: line)
            }
        }
    }

    func testResizeWiderPushesOnlyTheNeighbourDown() {
        let a = item(0, 0, 3, 3), b = item(3, 0, 3, 3), c = item(6, 0, 3, 3), d = item(0, 3, 3, 2), e = item(9, 0, 3, 5)
        var s = GridDragSession(id: a.id, mode: .resize, baseline: [a, b, c, d, e], columns: 12)
        // Drag the corner right by ~1.4 cells in small steps, like a real pointer.
        for i in 1...14 { s.update(translation: pt(cells: Double(i) / 10, rows: 0), cellWidth: cellW, rowHeight: rowH, gap: gap); assertOnlyCollidersMoved(s) }
        XCTAssertEqual(s.rect(for: a.id), GridRect(x: 0, y: 0, w: 4, h: 3))
        XCTAssertEqual(s.rect(for: b.id), GridRect(x: 3, y: 3, w: 3, h: 3), "B pushed directly below A")
        XCTAssertEqual(s.rect(for: c.id), c.rect, "C untouched")
        XCTAssertEqual(s.rect(for: d.id), d.rect, "D untouched (A did not grow downward)")
        XCTAssertEqual(s.rect(for: e.id), e.rect, "E untouched")
    }

    func testResizeBackRestoresOriginalLayout() {
        let a = item(0, 0, 3, 3), b = item(3, 0, 3, 3), c = item(0, 3, 6, 2)
        var s = GridDragSession(id: a.id, mode: .resize, baseline: [a, b, c], columns: 12)
        s.update(translation: pt(cells: 2, rows: 1), cellWidth: cellW, rowHeight: rowH, gap: gap)
        assertOnlyCollidersMoved(s)
        XCTAssertNotEqual(s.rect(for: b.id), b.rect)
        s.update(translation: .zero, cellWidth: cellW, rowHeight: rowH, gap: gap)
        XCTAssertEqual(s.preview.map(\.rect), [a, b, c].map(\.rect), "moving back must restore every widget")
    }

    func testResizeTallerPushesColumnBelowWithoutReshuffling() {
        let a = item(0, 0, 4, 2), below = item(0, 2, 4, 2), belowThat = item(0, 4, 4, 2), side = item(4, 0, 4, 6)
        var s = GridDragSession(id: a.id, mode: .resize, baseline: [a, below, belowThat, side], columns: 12)
        s.update(translation: pt(cells: 0, rows: 1), cellWidth: cellW, rowHeight: rowH, gap: gap)
        assertOnlyCollidersMoved(s)
        XCTAssertEqual(s.rect(for: below.id)?.y, 3)
        XCTAssertEqual(s.rect(for: belowThat.id)?.y, 5)
        XCTAssertEqual(s.rect(for: side.id), side.rect)
    }

    func testShrinkingNeverMovesOtherWidgets() {
        let a = item(0, 0, 6, 4), b = item(6, 0, 6, 2), c = item(0, 4, 3, 2)
        var s = GridDragSession(id: a.id, mode: .resize, baseline: [a, b, c], columns: 12)
        for i in 1...20 { s.update(translation: pt(cells: -Double(i) / 5, rows: -Double(i) / 10), cellWidth: cellW, rowHeight: rowH, gap: gap) }
        XCTAssertEqual(s.rect(for: a.id), GridRect(x: 0, y: 0, w: 2, h: 2))
        XCTAssertEqual(s.rect(for: b.id), b.rect)
        XCTAssertEqual(s.rect(for: c.id), c.rect, "gaps are left alone (Tidy Up closes them explicitly)")
    }

    func testResizeRespectsMinSizeAndRightEdge() {
        let a = item(8, 0, 3, 3, min: GridSize(2, 2))
        var s = GridDragSession(id: a.id, mode: .resize, baseline: [a], columns: 12)
        s.update(translation: pt(cells: 10, rows: 0), cellWidth: cellW, rowHeight: rowH, gap: gap)
        XCTAssertEqual(s.rect(for: a.id), GridRect(x: 8, y: 0, w: 4, h: 3), "clamped to grid width, origin fixed")
        s.update(translation: pt(cells: -10, rows: -10), cellWidth: cellW, rowHeight: rowH, gap: gap)
        XCTAssertEqual(s.rect(for: a.id), GridRect(x: 8, y: 0, w: 2, h: 2), "min size respected")
    }

    func testMoveIntoEmptySpaceLeavesOthersAlone() {
        let a = item(0, 0, 3, 3), b = item(3, 0, 3, 3), c = item(0, 3, 3, 3)
        var s = GridDragSession(id: a.id, mode: .move, baseline: [a, b, c], columns: 12)
        s.update(translation: pt(cells: 7, rows: 0), cellWidth: cellW, rowHeight: rowH, gap: gap)
        XCTAssertEqual(s.rect(for: a.id), GridRect(x: 7, y: 0, w: 3, h: 3))
        XCTAssertEqual(s.rect(for: b.id), b.rect)
        XCTAssertEqual(s.rect(for: c.id), c.rect, "C must not float up into A's old spot")
    }

    func testMoveOntoWidgetPushesItDown() {
        let a = item(0, 0, 3, 3), b = item(3, 0, 3, 3)
        var s = GridDragSession(id: a.id, mode: .move, baseline: [a, b], columns: 12)
        s.update(translation: pt(cells: 3, rows: 0), cellWidth: cellW, rowHeight: rowH, gap: gap)
        assertOnlyCollidersMoved(s)
        XCTAssertEqual(s.rect(for: b.id), GridRect(x: 3, y: 3, w: 3, h: 3))
    }

    @MainActor
    func testResizeEveryWidgetInDefaultWorkspacesHasNoSideEffects() {
        for ws in WorkspacePresets.defaults() {
            let items = ws.widgets.map { LayoutItem(id: $0.id, rect: $0.frame, minSize: WidgetRegistry.descriptor($0.kind)?.minSize ?? GridSize(1, 1)) }
            XCTAssertFalse(GridLayoutEngine.hasOverlaps(items), "\(ws.name) preset overlaps")
            for target in items {
                for (dx, dy) in [(1.0, 0.0), (0, 1), (2, 2), (-1, -1)] {
                    var s = GridDragSession(id: target.id, mode: .resize, baseline: items, columns: ws.columns)
                    s.update(translation: pt(cells: dx, rows: dy), cellWidth: cellW, rowHeight: rowH, gap: gap)
                    assertOnlyCollidersMoved(s)
                    XCTAssertEqual(s.rect(for: target.id)?.x, target.rect.x)
                    XCTAssertEqual(s.rect(for: target.id)?.y, target.rect.y)
                }
            }
        }
    }

    func testTidyUpClosesGaps() {
        let a = item(0, 2, 3, 2), b = item(3, 5, 3, 2)
        let out = GridLayoutEngine.compact([a, b])
        XCTAssertEqual(out.map(\.rect.y), [0, 0])
        XCTAssertFalse(GridLayoutEngine.hasOverlaps(out))
    }

    func testFirstFreeSlotAndNeighbours() {
        let a = item(0, 0, 4, 2), b = item(4, 0, 4, 2)
        XCTAssertEqual(GridLayoutEngine.firstFreeSlot(for: GridSize(4, 2), in: [a, b], columns: 12), GridRect(x: 8, y: 0, w: 4, h: 2))
        XCTAssertEqual(GridLayoutEngine.firstFreeSlot(for: GridSize(5, 2), in: [a, b], columns: 12), GridRect(x: 0, y: 2, w: 5, h: 2))
        XCTAssertEqual(GridLayoutEngine.neighbor(of: a.id, direction: .right, in: [a, b]), b.id)
        XCTAssertNil(GridLayoutEngine.neighbor(of: a.id, direction: .left, in: [a, b]))
    }
}

@MainActor
final class WorkspaceStoreTests: XCTestCase {
    func testCanDeleteEveryWorkspaceIncludingDefaultsAndLast() {
        let store = WorkspaceStore.shared
        let saved = store.workspaces
        defer { store.workspaces = saved; store.selectedID = saved.first?.id; store.saveNow() }
        store.workspaces = WorkspacePresets.defaults()
        store.select(store.workspaces[0].id)
        let names = store.workspaces.map(\.name)
        XCTAssertEqual(names, ["Home", "Dev", "Finance", "Health"])
        // Delete the selected default: selection moves to a neighbour.
        store.deleteWorkspace(store.workspaces[0].id)
        XCTAssertEqual(store.workspaces.map(\.name), ["Dev", "Finance", "Health"])
        XCTAssertEqual(store.current?.name, "Dev")
        // Delete everything, including the last one.
        for ws in store.workspaces { store.deleteWorkspace(ws.id) }
        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertNil(store.current)
        // Adding works again from empty.
        store.addWorkspace(name: "Fresh")
        XCTAssertEqual(store.current?.name, "Fresh")
        XCTAssertNotNil(store.addWidget(kind: PlaceholderWidget.kind))
    }

    func testDeletedWorkspacesStayDeletedAfterReload() {
        let store = WorkspaceStore.shared
        let saved = store.workspaces
        defer { store.workspaces = saved; store.saveNow() }
        store.workspaces = []
        store.saveNow()
        let reloaded = WorkspaceStore()   // re-reads the database like a relaunch
        XCTAssertTrue(reloaded.workspaces.isEmpty, "defaults must not be re-seeded after the user deleted them")
    }

    func testExportImportRoundTrip() throws {
        let store = WorkspaceStore.shared
        let saved = store.workspaces
        defer { store.workspaces = saved; store.saveNow() }
        store.workspaces = WorkspacePresets.defaults()
        let data = try store.exportJSON()
        store.workspaces = []
        try store.importJSON(data, replace: true)
        XCTAssertEqual(store.workspaces.map(\.name), ["Home", "Dev", "Finance", "Health"])
        XCTAssertEqual(store.workspaces.map(\.widgets.count), WorkspacePresets.defaults().map(\.widgets.count))
    }
}
