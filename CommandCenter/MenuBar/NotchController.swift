import AppKit
import SwiftUI

/// Dynamic-Island–style panel that grows out of the MacBook notch (or, on screens without a notch,
/// from the top-centre of the menu bar). Collapsed it hides inside the notch; with a running pomodoro
/// or active AI agents it widens into a "live activity"; hovering or ⌘⇧Space expands it into the
/// full menu bar panel. Can be disabled in Settings → General.
@MainActor
final class NotchController: NSObject, NSWindowDelegate {
    static let shared = NotchController()

    enum Mode: Equatable { case hidden, collapsed, live, expanded }

    private var window: NotchWindow?
    private(set) var mode: Mode = .hidden
    private var hoverTask: Task<Void, Never>?
    private var activityTimer: UUID?
    let state = NotchState()

    // MARK: Settings
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.notchEnabled) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.notchEnabled); shared.applySettings() }
    }
    static var hoverToOpen: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.notchHover) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.notchHover) }
    }
    static var showLiveActivity: Bool {
        get { UserDefaults.standard.object(forKey: SettingsKey.notchLive) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.notchLive); shared.refreshActivity() }
    }

    // MARK: Geometry (pure, unit-tested)
    struct Notch: Equatable { var rect: CGRect; var isHardware: Bool }

    /// Notch rectangle in screen coordinates: the real notch when present, otherwise a virtual one
    /// centred in the menu bar.
    static func notch(screenFrame: CGRect, safeTop: CGFloat, auxLeft: CGRect?, auxRight: CGRect?, menuBarHeight: CGFloat) -> Notch {
        if safeTop > 0, let l = auxLeft, let r = auxRight, l.width > 0, r.width > 0 {
            let x = l.maxX, w = r.minX - l.maxX
            return Notch(rect: CGRect(x: x, y: screenFrame.maxY - safeTop, width: w, height: safeTop), isHardware: true)
        }
        let w: CGFloat = 190, h = max(22, menuBarHeight)
        return Notch(rect: CGRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h), isHardware: false)
    }

    static let liveWing: CGFloat = 84
    static let expandedSize = CGSize(width: 680, height: 470)

    static func frame(for mode: Mode, notch: Notch, screenFrame: CGRect) -> CGRect {
        let n = notch.rect
        switch mode {
        case .hidden, .collapsed:
            return n
        case .live:
            return n.insetBy(dx: -liveWing, dy: 0)
        case .expanded:
            let w = max(expandedSize.width, n.width + 2 * liveWing)
            var x = n.midX - w / 2
            x = min(max(screenFrame.minX + 6, x), screenFrame.maxX - w - 6)
            let h = expandedSize.height + n.height
            return CGRect(x: x, y: screenFrame.maxY - h, width: w, height: h)
        }
    }

    // MARK: Lifecycle
    func install() {
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        applySettings()
    }

    func applySettings() {
        if Self.isEnabled {
            if window == nil { makeWindow() }
            if activityTimer == nil { activityTimer = TickScheduler.shared.subscribe(every: 2) { [weak self] in self?.refreshActivity() } }
            refreshActivity()
        } else {
            if let t = activityTimer { TickScheduler.shared.unsubscribe(t); activityTimer = nil }
            window?.orderOut(nil)
            window = nil
            mode = .hidden
        }
    }

    private func makeWindow() {
        let w = NotchWindow()
        w.delegate = self
        let host = NSHostingView(rootView: NotchRootView(state: state, model: StatusItemController.shared.model))
        host.translatesAutoresizingMaskIntoConstraints = false
        let tracker = NotchTrackingView()
        tracker.onHover = { [weak self] inside in self?.hoverChanged(inside) }
        tracker.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: tracker.leadingAnchor), host.trailingAnchor.constraint(equalTo: tracker.trailingAnchor),
            host.topAnchor.constraint(equalTo: tracker.topAnchor), host.bottomAnchor.constraint(equalTo: tracker.bottomAnchor),
        ])
        w.contentView = tracker
        window = w
        set(.collapsed, animated: false)
        w.orderFrontRegardless()
    }

    @objc private func screensChanged() { if mode != .hidden { set(mode == .expanded ? .expanded : baseMode, animated: false) } }

    var currentNotch: Notch {
        let s = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
        let menuBar = s.frame.maxY - s.visibleFrame.maxY
        return Self.notch(screenFrame: s.frame, safeTop: s.safeAreaInsets.top, auxLeft: s.auxiliaryTopLeftArea, auxRight: s.auxiliaryTopRightArea,
                          menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness)
    }

    private var screenFrame: CGRect {
        (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]).frame
    }

    /// Collapsed or live, depending on whether anything is running.
    private var baseMode: Mode { Self.showLiveActivity && state.hasActivity ? .live : .collapsed }

    func set(_ m: Mode, animated: Bool = true) {
        guard let window else { return }
        let notch = currentNotch
        state.notchHeight = notch.rect.height
        state.notchWidth = notch.rect.width
        state.isHardwareNotch = notch.isHardware
        let target = Self.frame(for: m, notch: notch, screenFrame: screenFrame)
        let changed = mode != m
        mode = m
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { state.mode = m }
        if animated && changed {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                window.animator().setFrame(target, display: true)
            }
        } else {
            window.setFrame(target, display: true)
        }
        if m == .expanded {
            window.makeKeyAndOrderFront(nil)   // non-activating: dashboard window stays put
            StatusItemController.shared.model.focusToken += 1
        }
    }

    func refreshActivity() {
        state.pomodoroRunning = PomodoroEngine.shared.isRunning
        state.pomodoroRemaining = PomodoroEngine.shared.remaining
        state.pomodoroPhase = PomodoroEngine.shared.phase.rawValue
        state.agentsRunning = AgentActivity.runningCount() + AIService.shared.activeJobs
        if mode == .collapsed || mode == .live, baseMode != mode { set(baseMode) }
    }

    // MARK: Interaction
    func toggle(tab: MenuBarModel.Tab?, prefill: String? = nil) {
        let model = StatusItemController.shared.model
        if mode == .expanded && (tab == nil || tab == model.tab) && prefill == nil { collapse(); return }
        if let tab { model.tab = tab }
        if let prefill { model.input = prefill }
        set(.expanded)
    }

    func collapse() { if mode == .expanded { set(baseMode) } }

    private func hoverChanged(_ inside: Bool) {
        hoverTask?.cancel()
        if inside {
            guard Self.hoverToOpen, mode != .expanded else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                self?.set(.expanded)
            }
        } else if mode == .expanded {
            // Leaving the island collapses it unless the user is typing in it.
            hoverTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled, let self else { return }
                if !(self.window?.firstResponder is NSTextView) { self.collapse() }
            }
        }
    }

    func windowDidResignKey(_ notification: Notification) { collapse() }
}

/// Observable state that drives the island's SwiftUI content.
@MainActor @Observable
final class NotchState {
    var mode: NotchController.Mode = .collapsed
    var notchHeight: CGFloat = 32
    var notchWidth: CGFloat = 190
    var isHardwareNotch = false
    var pomodoroRunning = false
    var pomodoroRemaining: TimeInterval = 0
    var pomodoroPhase = ""
    var agentsRunning = 0
    var hasActivity: Bool { pomodoroRunning || agentsRunning > 0 }
}

final class NotchWindow: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 190, height: 32), styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)   // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { MainActor.assumeIsolated { NotchController.shared.collapse() } }
}

/// Reports hover over the whole island, including while it animates.
final class NotchTrackingView: NSView {
    var onHover: ((Bool) -> Void)?
    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

/// The island itself: black, flat, rounded at the bottom like the hardware notch.
struct NotchRootView: View {
    let state: NotchState
    let model: MenuBarModel

    var body: some View {
        let radius: CGFloat = state.mode == .expanded ? 22 : state.notchHeight * 0.42
        VStack(spacing: 0) {
            topStrip.frame(height: state.notchHeight)
            if state.mode == .expanded {
                MenuBarView(model: model)
                    .frame(width: NotchController.expandedSize.width, height: NotchController.expandedSize.height)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
                .fill(Color.black)
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous))
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
        .onTapGesture { if state.mode != .expanded { NotchController.shared.set(.expanded) } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Center island")
    }

    /// Live activity: pomodoro on the left of the notch, agent activity on the right.
    @ViewBuilder private var topStrip: some View {
        HStack(spacing: 0) {
            if state.mode == .live || state.mode == .expanded {
                HStack(spacing: 5) {
                    if state.pomodoroRunning {
                        Image(systemName: "timer").foregroundStyle(.red)
                        Text(String(format: "%d:%02d", Int(state.pomodoroRemaining) / 60, Int(state.pomodoroRemaining) % 60))
                            .monospacedDigit().foregroundStyle(.white)
                    } else if state.mode == .expanded {
                        Image(systemName: "square.grid.2x2").foregroundStyle(.white.opacity(0.7))
                        Text("Command Center").foregroundStyle(.white.opacity(0.85))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(width: NotchController.liveWing, alignment: .center)
                .padding(.leading, state.mode == .expanded ? 14 : 0)
                .fixedSize()
            }
            Spacer(minLength: state.notchWidth)
            if state.mode == .live || state.mode == .expanded {
                HStack(spacing: 5) {
                    if state.agentsRunning > 0 {
                        ProgressRing(fraction: min(1, Double(state.agentsRunning) / 4), tint: .green, lineWidth: 2.5).frame(width: 13, height: 13)
                        Text("\(state.agentsRunning)").monospacedDigit().foregroundStyle(.white)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .frame(width: NotchController.liveWing, alignment: .center)
                .padding(.trailing, state.mode == .expanded ? 14 : 0)
                .accessibilityLabel("\(state.agentsRunning) AI agents running")
            }
        }
    }
}
