import AppKit
import Foundation

/// App-wide pomodoro state so the menu bar, command palette and widgets share one timer.
@MainActor @Observable
final class PomodoroEngine {
    static let shared = PomodoroEngine()

    enum Phase: String { case idle = "Ready", focus = "Focus", shortBreak = "Short Break", longBreak = "Long Break" }

    var phase: Phase = .idle
    var remaining: TimeInterval = 25 * 60
    var total: TimeInterval = 25 * 60
    var isRunning = false
    var task: String?
    var completedInCycle = 0
    var config = PomodoroConfiguration()

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var phaseStart = Date()
    @ObservationIgnored private var endDate = Date()
    @ObservationIgnored private var activationObserver: Any?

    var fraction: Double { total > 0 ? 1 - remaining / total : 0 }

    func apply(_ c: PomodoroConfiguration) {
        config = c
        if phase == .idle { total = Double(c.focusMinutes * 60); remaining = total }
    }

    func start(task: String? = nil) {
        if let task { self.task = task }
        if phase == .idle || (task != nil && phase != .focus) { begin(.focus) }
        else if !isRunning { remaining > 0 ? resume() : begin(.focus) }
        WidgetBus.shared.toast("\(phase.rawValue) started\(self.task.map { ": \($0)" } ?? "")", symbol: "timer")
    }

    func begin(_ p: Phase) {
        phase = p
        let minutes: Int = switch p {
        case .focus, .idle: config.focusMinutes
        case .shortBreak: config.shortBreak
        case .longBreak: config.longBreak
        }
        total = Double(minutes * 60)
        remaining = total
        phaseStart = Date()
        resume()
    }

    func resume() {
        isRunning = true
        endDate = Date().addingTimeInterval(remaining)
        timer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { _ in Task { @MainActor in PomodoroEngine.shared.tick() } }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
        updateBlocking()
    }

    func pause() {
        isRunning = false
        timer?.invalidate(); timer = nil
        updateBlocking()
    }

    func reset() {
        pause()
        phase = .idle
        total = Double(config.focusMinutes * 60)
        remaining = total
    }

    func skip() { finishPhase(logged: false) }

    private func tick() {
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finishPhase(logged: true) }
    }

    func finishPhase(logged: Bool) {
        pause()
        if phase == .focus {
            if logged {
                let minutes = Int((Date().timeIntervalSince(phaseStart) / 60).rounded())
                PomodoroStore.log(PomodoroSession(start: phaseStart, end: Date(), minutes: max(1, minutes), task: task))
                HabitStore.signal(config.habitName)
                WidgetBus.shared.publish(.pomodoroCompleted(task: task, minutes: minutes))
                Notifier.post("Pomodoro complete", task.map { "Nice work on \($0). Take a break." } ?? "Take a break.")
                NSSound(named: "Glass")?.play()
            }
            completedInCycle += 1
            let next: Phase = completedInCycle % max(1, config.longBreakEvery) == 0 ? .longBreak : .shortBreak
            if config.autoStartBreaks { begin(next) } else { phase = next; total = Double((next == .longBreak ? config.longBreak : config.shortBreak) * 60); remaining = total }
        } else {
            if logged { Notifier.post("Break over", "Ready for the next focus session?") }
            phase = .idle
            total = Double(config.focusMinutes * 60)
            remaining = total
        }
    }

    // MARK: Distraction blocking (hides listed apps while focusing)
    private func updateBlocking() {
        let active = isRunning && phase == .focus && config.blockApps
        if active && activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                Task { @MainActor in
                    let engine = PomodoroEngine.shared
                    if let id = app.bundleIdentifier, engine.config.blockedBundleIDs.contains(id) {
                        app.hide()
                        WidgetBus.shared.toast("\(app.localizedName ?? id) is blocked during focus", symbol: "hand.raised")
                    }
                }
            }
            for app in NSWorkspace.shared.runningApplications where config.blockedBundleIDs.contains(app.bundleIdentifier ?? "") { app.hide() }
        } else if !active, let obs = activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            activationObserver = nil
        }
    }
}
