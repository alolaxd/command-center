import AppKit
import SwiftUI
import XCTest
@testable import Command_Center

@MainActor
final class TerminalRenderTests: XCTestCase {
    func testTerminalPaneLaysOutWithRealSize() {
        let d = TerminalPanesWidget.descriptor
        let inst = WidgetInstance(kind: d.kind, frame: GridRect(x: 0, y: 0, w: 6, h: 4), config: d.defaultConfig)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: WidgetCardView(instance: inst, isFocused: false, isDragging: false, onMove: { _ in }, onResize: { _ in })
            .frame(width: 700, height: 420))
        w.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        let tab = TerminalPanesWidget.decodeConfig(inst.config).tabs[0]
        let session = TerminalPanesStore.session(for: tab.panes[0], instance: inst.id)
        print("CCDBG superview=\(String(describing: session.view.superview)) frame=\(session.view.frame) window=\(String(describing: session.view.window))")
        XCTAssertNotNil(session.view.window, "terminal view is in the window")
        XCTAssertGreaterThan(session.view.frame.width, 300)
        XCTAssertGreaterThan(session.view.frame.height, 150)
        w.orderOut(nil)
    }
}

final class ProcessNameTests: XCTestCase {
    func testVersionNamedClaudeBinaryShowsAsClaude() {
        let ps = Shell.runSync("/bin/ps", ["-axo", "pid=,comm="]).stdout
        guard let line = ps.split(separator: "\n").first(where: { $0.hasSuffix(" claude") }),
              let pid = pid_t(line.trimmingCharacters(in: .whitespaces).split(separator: " ").first ?? "") else {
            return   // Claude Code not running here
        }
        XCTAssertEqual(SystemSampler.processName(pid), "claude")
    }
}

/// Pixel-level check that terminal content actually reaches the screen.
@MainActor
final class TerminalPixelTests: XCTestCase {
    static func windowImage(_ window: NSWindow) -> CGImage? {
        typealias Fn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let h = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(h, "CGWindowListCreateImage") else { return nil }
        return unsafeBitCast(sym, to: Fn.self)(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue()
    }

    /// Fraction of pixels in the centre region that match the terminal background colour.
    private func terminalCoverage<V: View>(_ view: V) -> Double {
        let w = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 500, height: 320), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .aqua)
        w.contentView = NSHostingView(rootView: view.frame(width: 500, height: 320).background(Color.white))
        w.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        defer { w.orderOut(nil) }
        guard let img = Self.windowImage(w), let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return -1 }
        let bpr = img.bytesPerRow, bpp = img.bitsPerPixel / 8
        var hits = 0, total = 0
        for y in stride(from: img.height / 3, to: img.height * 2 / 3, by: 4) {
            for x in stride(from: img.width / 3, to: img.width * 2 / 3, by: 4) {
                let o = y * bpr + x * bpp
                let (b, g, r) = (Int(p[o]), Int(p[o + 1]), Int(p[o + 2]))
                if r < 40 && g < 40 && b < 40 { hits += 1 }   // dark terminal background (BGRA)
                total += 1
            }
        }
        return Double(hits) / Double(max(1, total))
    }

    func testTerminalVisibleWithAndWithoutClipping() {
        let s = TerminalSession(cwd: NSTemporaryDirectory())
        let plain = terminalCoverage(TerminalHostView(session: s))
        let clipped = terminalCoverage(TerminalHostView(session: s).clipShape(RoundedRectangle(cornerRadius: 12)))
        print("CCPIX plain=\(plain) clipped=\(clipped)")
        XCTAssertGreaterThan(plain, 0.8, "terminal draws its background")
        XCTAssertGreaterThan(clipped, 0.8, "terminal still visible inside a clipped container")
        s.terminate()
    }

    /// Bright (text) pixels inside the window after the session prints a lot of text.
    private func textPixels<V: View>(_ view: V, session: TerminalSession, size: NSSize = NSSize(width: 700, height: 420)) -> Int {
        let w = NSWindow(contentRect: NSRect(origin: NSPoint(x: 60, y: 60), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color.black))
        w.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        session.runLine("clear; for i in 1 2 3 4 5 6 7 8; do echo MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM; done")
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        defer { w.orderOut(nil) }
        guard let img = Self.windowImage(w), let data = img.dataProvider?.data, let p = CFDataGetBytePtr(data) else { return -1 }
        var n = 0
        for y in stride(from: 0, to: img.height, by: 2) { for x in stride(from: 0, to: img.width, by: 2) {
            let o = y * img.bytesPerRow + x * (img.bitsPerPixel / 8)
            if p[o] > 200 && p[o + 1] > 200 && p[o + 2] > 200 { n += 1 }
        } }
        return n
    }

    func testTerminalTextRendersInDashboardContainers() {
        let s1 = TerminalSession(cwd: NSTemporaryDirectory())
        let plain = textPixels(TerminalHostView(session: s1), session: s1)
        let d = TerminalPanesWidget.descriptor
        let inst = WidgetInstance(kind: d.kind, frame: GridRect(x: 0, y: 0, w: 6, h: 4), config: d.defaultConfig)
        let pane = TerminalPanesStore.session(for: TerminalPanesWidget.decodeConfig(inst.config).tabs[0].panes[0], instance: inst.id)
        let card = textPixels(WidgetCardView(instance: inst, isFocused: false, isDragging: false, onMove: { _ in }, onResize: { _ in }), session: pane)
        let scrolled = textPixels(ScrollView { WidgetCardView(instance: inst, isFocused: false, isDragging: false, onMove: { _ in }, onResize: { _ in }).frame(width: 680, height: 400) }, session: pane)
        print("CCPIX text plain=\(plain) card=\(card) scrolled=\(scrolled)")
        XCTAssertGreaterThan(plain, 500)
        XCTAssertGreaterThan(card, 500, "text visible in a widget card")
        XCTAssertGreaterThan(scrolled, 500, "text visible inside the dashboard ScrollView")
    }

    func testTerminalVisibleInRealContainers() {
        let d = TerminalPanesWidget.descriptor
        let inst = WidgetInstance(kind: d.kind, frame: GridRect(x: 0, y: 0, w: 6, h: 4), config: d.defaultConfig)
        let card = terminalCoverage(WidgetCardView(instance: inst, isFocused: false, isDragging: false, onMove: { _ in }, onResize: { _ in }))
        let host = terminalCoverage(WidgetContentHost(instance: inst, isZen: false, descriptor: d))
        let widget = terminalCoverage(d.makeView(inst, false) { _ in })
        let q = TerminalManager.shared.quick
        let quick = terminalCoverage(TerminalHostView(session: q))
        let st = NotchState(); st.mode = .expanded; st.notchHeight = 32
        let notch = terminalCoverage(NotchRootView(state: st, model: MenuBarModel()).frame(width: 500, height: 320))
        let menu = terminalCoverage(MenuBarView(model: MenuBarModel()))
        print("CCPIX card=\(card) host=\(host) widget=\(widget) quick=\(quick) notch=\(notch) menu=\(menu)")
    }
}


@MainActor
final class TerminalOwnershipTests: XCTestCase {
    func testHiddenHostDoesNotStealTerminalFromVisibleOne() {
        let s = TerminalSession(cwd: NSTemporaryDirectory())
        let visible = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        // Like the real drop-down / island: a non-activating panel that becomes key when shown.
        let hidden = OwnershipPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let token = FocusToken()
        visible.contentView = NSHostingView(rootView: TokenHost(token: token, session: s))
        hidden.contentView = NSHostingView(rootView: TokenHost(token: token, session: s))   // not shown yet
        visible.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(s.view.window === visible, "the visible host owns the terminal")
        hidden.makeKeyAndOrderFront(nil)
        token.value += 1   // the app bumps MenuBarModel.focusToken whenever a panel is shown
        XCTAssertTrue(waitUntil(3) { s.view.window === hidden })
        XCTAssertTrue(s.view.window === hidden, "a host whose window becomes visible/key re-claims it")
        visible.orderOut(nil); hidden.orderOut(nil); s.terminate()
    }

    func testTwoTerminalWidgetsGetSeparateShells() {
        let d = TerminalPanesWidget.descriptor
        let a = WidgetInstance(kind: d.kind, frame: GridRect(x: 0, y: 0, w: 6, h: 4), config: d.defaultConfig)
        let b = WidgetInstance(kind: d.kind, frame: GridRect(x: 0, y: 0, w: 6, h: 4), config: d.defaultConfig)
        let pane = TerminalPanesWidget.decodeConfig(d.defaultConfig).tabs[0].panes[0]
        XCTAssertFalse(TerminalPanesStore.session(for: pane, instance: a.id) === TerminalPanesStore.session(for: pane, instance: b.id))
    }
}

private final class OwnershipPanel: NSPanel { override var canBecomeKey: Bool { true } }

@MainActor @Observable private final class FocusToken { var value = 0 }
private struct TokenHost: View {
    let token: FocusToken
    let session: TerminalSession
    var body: some View { TerminalHostView(session: session).id(0).onChange(of: token.value) {}.overlay(Text("\(token.value)").opacity(0)) }
}
