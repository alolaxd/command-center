import AppKit
import SwiftUI

/// Menu bar item + a non-activating panel. The panel takes keyboard input without
/// activating the app, so clicking the icon never brings the dashboard window forward.
/// The icon is a rounded square with a grid that fills clockwise as AI agent jobs run.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    static let shared = StatusItemController()

    private var item: NSStatusItem!
    private var panel: MenuBarPanel!
    private var lastFraction: Double = -1
    private var lastClosed = Date.distantPast
    let model = MenuBarModel()
    let panelSize = NSSize(width: 660, height: 470)

    var isShown: Bool { panel?.isVisible ?? false }

    func install() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(clicked(_:))
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Command Center")
        setActivity(0)

        panel = MenuBarPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        panel.delegate = self
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.separatorColor.cgColor
        let host = NSHostingView(rootView: MenuBarView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: effect.leadingAnchor), host.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            host.topAnchor.constraint(equalTo: effect.topAnchor), host.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        panel.contentView = effect

        // Refresh the activity ring from running agents + in-app AI jobs (coalesced 5s tick).
        _ = TickScheduler.shared.subscribe(every: 5) { [weak self] in
            let running = AgentActivity.runningCount() + AIService.shared.activeJobs
            self?.setActivity(min(1, Double(running) / 4))
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            close()
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboard), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Command Center", action: #selector(quitCompletely), keyEquivalent: "q").target = self
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            // A click on the icon while the panel is open first resigns key (closing it); don't immediately reopen.
            if Date().timeIntervalSince(lastClosed) < 0.25 { return }
            toggle(tab: nil)
        }
    }

    func toggle(tab: MenuBarModel.Tab?, prefill: String? = nil) {
        if NotchController.isEnabled {
            closeDropdown()
            NotchController.shared.toggle(tab: tab, prefill: prefill)
            return
        }
        if isShown && (tab == nil || tab == model.tab) && prefill == nil {
            close()
            return
        }
        if let tab { model.tab = tab }
        if let prefill { model.input = prefill }
        show()
    }

    func show() {
        guard let button = item.button, let bw = button.window else { return }
        let buttonFrame = bw.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = bw.screen ?? NSScreen.main
        var x = buttonFrame.midX - panelSize.width / 2
        if let vis = screen?.visibleFrame { x = min(max(vis.minX + 8, x), vis.maxX - panelSize.width - 8) }
        panel.setFrame(NSRect(x: x, y: buttonFrame.minY - panelSize.height - 6, width: panelSize.width, height: panelSize.height), display: true)
        panel.makeKeyAndOrderFront(nil)   // non-activating: the app (and its dashboard window) stays in the background
        item.button?.highlight(true)
        model.focusToken += 1
    }

    /// Closes whichever panel is open (island or dropdown).
    func close() {
        NotchController.shared.collapse()
        closeDropdown()
    }

    private func closeDropdown() {
        guard panel?.isVisible == true else { return }
        panel.orderOut(nil)
        item.button?.highlight(false)
        lastClosed = Date()
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    @objc func openDashboard() {
        close()
        AppState.openMainWindow()
    }

    @objc private func openSettings() {
        close()
        AppState.showInDock()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quitCompletely() { AppState.quitCompletely() }

    func setActivity(_ fraction: Double) {
        guard abs(fraction - lastFraction) > 0.001 else { return }
        lastFraction = fraction
        item.button?.image = Self.icon(fraction: fraction)
        item.button?.toolTip = fraction > 0 ? "Command Center — AI agents active" : "Command Center"
    }

    static func icon(fraction: Double) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let rect = NSRect(x: 2, y: 2, width: 14, height: 14)
            let outline = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
            outline.lineWidth = 1.4
            NSColor.black.setFill()
            for (gx, gy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
                NSBezierPath(roundedRect: NSRect(x: 5 + CGFloat(gx) * 4.5, y: 5 + CGFloat(gy) * 4.5, width: 3.5, height: 3.5),
                             xRadius: 0.8, yRadius: 0.8).fill()
            }
            if fraction <= 0 {
                NSColor.black.setStroke(); outline.stroke()
            } else {
                NSColor.black.withAlphaComponent(0.35).setStroke(); outline.stroke()
                // Clockwise wedge from 12 o'clock used as a clip for the solid outline.
                NSGraphicsContext.saveGraphicsState()
                let center = NSPoint(x: 9, y: 9)
                let wedge = NSBezierPath()
                wedge.move(to: center)
                wedge.appendArc(withCenter: center, radius: 14, startAngle: 90, endAngle: 90 - 360 * CGFloat(fraction), clockwise: true)
                wedge.close()
                wedge.addClip()
                NSColor.black.setStroke()
                let thick = NSBezierPath(roundedRect: rect, xRadius: 3.5, yRadius: 3.5)
                thick.lineWidth = 2.2
                thick.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Borderless floating panel that can become key without activating the app.
final class MenuBarPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        animationBehavior = .utilityWindow
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { MainActor.assumeIsolated { StatusItemController.shared.close() } }
}

/// Global app hooks set up by SwiftUI scenes.
@MainActor
enum AppState {
    static var openWindowAction: ((String) -> Void)?
    /// Set by "Quit Completely"; otherwise ⌘Q only hides Command Center to the menu bar.
    static var reallyQuit = false

    static func openMainWindow() {
        showInDock()
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Command Center" }), w.isVisible || w.isMiniaturized {
            w.makeKeyAndOrderFront(nil)
        } else {
            openWindowAction?("main")
        }
    }

    static func showInDock() {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }

    /// ⌘Q: close the dashboard and keep running as a menu bar utility.
    static func hideToMenuBar() {
        WorkspaceStore.shared.saveNow()
        for w in NSApp.windows where !(w is MenuBarPanel) && w.isVisible && w.className != "NSStatusBarWindow" { w.close() }
        NSApp.setActivationPolicy(.accessory)
        if !UserDefaults.standard.bool(forKey: "hint.hiddenToMenuBar") {
            UserDefaults.standard.set(true, forKey: "hint.hiddenToMenuBar")
            Notifier.post("Still running in the menu bar", "Click the grid icon or press ⌘⇧Space. Use ⌥⌘Q to quit completely.")
        }
    }

    static func quitCompletely() {
        reallyQuit = true
        NSApp.terminate(nil)
    }
}
