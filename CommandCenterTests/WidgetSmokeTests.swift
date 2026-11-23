import AppKit
import SwiftUI
import XCTest
@testable import Command_Center

/// Renders every registered widget (and its settings editor) in a real window.
@MainActor
final class WidgetSmokeTests: XCTestCase {
    func testRegistryIsCompleteAndConsistent() {
        let kinds = WidgetRegistry.all.map(\.kind)
        XCTAssertEqual(Set(kinds).count, kinds.count, "duplicate widget kinds")
        XCTAssertGreaterThanOrEqual(kinds.count, 31, "every spec'd widget registered (30 + AI chat + placeholder)")
        for d in WidgetRegistry.all {
            XCTAssertLessThanOrEqual(d.minSize.w, d.defaultSize.w, d.kind)
            XCTAssertLessThanOrEqual(d.minSize.h, d.defaultSize.h, d.kind)
            XCTAssertFalse(d.title.isEmpty); XCTAssertFalse(d.summary.isEmpty)
            XCTAssertNotNil(NSImage(systemSymbolName: d.symbol, accessibilityDescription: nil), "missing SF Symbol \(d.symbol) for \(d.kind)")
            XCTAssertNotNil(try? JSONSerialization.jsonObject(with: d.defaultConfig), "default config must be JSON for \(d.kind)")
        }
        for (cat, items) in WidgetRegistry.grouped() { XCTAssertFalse(items.isEmpty, cat.rawValue) }
    }

    func testEveryWidgetAndSettingsEditorRenders() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700), styleMask: [.titled], backing: .buffered, defer: false)
        for d in WidgetRegistry.all {
            let inst = WidgetInstance(kind: d.kind, frame: GridRect(x: 0, y: 0, w: d.defaultSize.w, h: d.defaultSize.h), config: d.defaultConfig)
            let card = WidgetCardView(instance: inst, isFocused: true, isDragging: false, onMove: { _ in }, onResize: { _ in })
                .frame(width: CGFloat(d.defaultSize.w) * 95, height: CGFloat(d.defaultSize.h) * 90)
            let host = NSHostingView(rootView: card)
            window.contentView = host
            window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
            XCTAssertGreaterThan(host.fittingSize.width, 0, "\(d.kind) rendered nothing")
            if d.hasSettings {
                let editor = NSHostingView(rootView: d.makeSettings(d.defaultConfig) { _ in }.frame(width: 340))
                window.contentView = editor
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                XCTAssertGreaterThan(editor.fittingSize.height, 0, "\(d.kind) settings rendered nothing")
            }
        }
        window.orderOut(nil)
    }

    func testMenuBarPanelAndIconRender() {
        for f in [0.0, 0.25, 0.5, 1.0] {
            let img = StatusItemController.icon(fraction: f)
            XCTAssertTrue(img.isTemplate)
            XCTAssertNotNil(img.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
        let model = MenuBarModel()
        for tab in MenuBarModel.Tab.allCases {
            model.tab = tab
            let host = NSHostingView(rootView: MenuBarView(model: model))
            host.frame = NSRect(x: 0, y: 0, width: 660, height: 470)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }
}
