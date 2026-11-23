import AppKit
import SwiftUI
import XCTest
@testable import Command_Center

/// A non-activating panel can be key even though the test host app is in the background.
private final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

/// Drives the real DashboardView with synthesized mouse events (the same path as a user's pointer).
@MainActor
final class DashboardInteractionTests: XCTestCase {
    private var window: NSWindow!
    private let size = NSSize(width: 1200, height: 800)

    private struct Host: View {
        var body: some View {
            if let ws = WorkspaceStore.shared.current { DashboardView(workspace: ws) }
        }
    }

    override func setUp() async throws {
        UserDefaults.standard.set(84.0, forKey: SettingsKey.rowHeight)
        let store = WorkspaceStore.shared
        var ws = Workspace(name: "UITest-\(UUID().uuidString.prefix(4))", symbol: "testtube.2")
        func add(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            ws.widgets.append(WidgetInstance(kind: PlaceholderWidget.kind, frame: GridRect(x: x, y: y, w: w, h: h),
                                             config: PlaceholderWidget.descriptor.defaultConfig))
        }
        add(0, 0, 3, 3); add(3, 0, 3, 3); add(6, 0, 3, 3); add(0, 3, 3, 2); add(9, 0, 3, 5)
        store.workspaces.append(ws)
        store.select(ws.id)
        window = KeyPanel(contentRect: NSRect(origin: NSPoint(x: 100, y: 100), size: size), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: Host())
        window.makeKeyAndOrderFront(nil)
        pump(0.5)
        XCTAssertTrue(window.isKeyWindow, "test window must be key, like the real dashboard window during a drag")
    }

    override func tearDown() async throws {
        if let id = WorkspaceStore.shared.current?.id { WorkspaceStore.shared.deleteWorkspace(id) }
        window.orderOut(nil)
        window = nil
    }

    private func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

    /// Grid metrics identical to DashboardView's.
    private var cellW: CGFloat { (size.width - 24 - 10 * 11) / 12 }
    private func cellRect(_ r: GridRect) -> CGRect {
        CGRect(x: 12 + CGFloat(r.x) * (cellW + 10), y: 12 + CGFloat(r.y) * (84 + 10),
               width: CGFloat(r.w) * cellW + CGFloat(r.w - 1) * 10, height: CGFloat(r.h) * 84 + CGFloat(r.h - 1) * 10)
    }

    /// Converts a top-left (SwiftUI) point in the content view to window coordinates.
    private func windowPoint(_ p: CGPoint) -> NSPoint { NSPoint(x: p.x, y: window.contentView!.bounds.height - p.y) }

    private func send(_ type: NSEvent.EventType, _ p: CGPoint) {
        let e = NSEvent.mouseEvent(with: type, location: windowPoint(p), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
        window.sendEvent(e)
    }

    private func drag(from start: CGPoint, by delta: CGSize, steps: Int = 24) {
        send(.leftMouseDown, start)
        pump(0.05)
        for i in 1...steps {
            let f = CGFloat(i) / CGFloat(steps)
            send(.leftMouseDragged, CGPoint(x: start.x + delta.width * f, y: start.y + delta.height * f))
            pump(0.016)
        }
        send(.leftMouseUp, CGPoint(x: start.x + delta.width, y: start.y + delta.height))
        pump(0.6)
    }

    private var frames: [GridRect] { WorkspaceStore.shared.current!.widgets.map(\.frame) }

    func testResizeWiderWithMouseOnlyPushesNeighbour() {
        let before = frames
        let a = cellRect(before[0])
        // Grab the resize handle in A's bottom-right corner and drag one cell to the right.
        drag(from: CGPoint(x: a.maxX - 8, y: a.maxY - 8), by: CGSize(width: cellW + 10, height: 0))
        let after = frames
        XCTAssertEqual(after[0], GridRect(x: 0, y: 0, w: 4, h: 3), "A should be one column wider")
        XCTAssertEqual(after[1], GridRect(x: 3, y: 3, w: 3, h: 3), "B pushed straight down below A")
        XCTAssertEqual(after[2], before[2], "C untouched")
        XCTAssertEqual(after[3], before[3], "D untouched")
        XCTAssertEqual(after[4], before[4], "E untouched")
    }

    func testResizeTallerWithMouse() {
        let before = frames
        let c = cellRect(before[2])
        drag(from: CGPoint(x: c.maxX - 8, y: c.maxY - 8), by: CGSize(width: 0, height: 94 * 2))
        let after = frames
        XCTAssertEqual(after[2], GridRect(x: 6, y: 0, w: 3, h: 5))
        XCTAssertEqual(Array(after[0...1]) + [after[3], after[4]], Array(before[0...1]) + [before[3], before[4]], "nothing else moves")
    }

    func testMoveWithHeaderDrag() {
        let before = frames
        let d = cellRect(before[3])
        // Header is the top 28pt of the card; grab its left side (away from buttons).
        drag(from: CGPoint(x: d.minX + 30, y: d.minY + 14), by: CGSize(width: (cellW + 10) * 3, height: 0))
        let after = frames
        XCTAssertEqual(after[3], GridRect(x: 3, y: 3, w: 3, h: 2), "D moved three columns right")
        XCTAssertEqual(after[0], before[0])
        XCTAssertEqual(after[2], before[2])
        XCTAssertFalse(GridLayoutEngine.hasOverlaps(WorkspaceStore.shared.gridItems(WorkspaceStore.shared.current!)))
    }
}
