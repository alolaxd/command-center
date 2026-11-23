import SwiftUI

/// One coalesced timer for every polling widget. Subscribers declare an interval;
/// the scheduler fires a single 1 Hz timer (with generous tolerance) only while
/// subscribers exist, and calls each one when its interval has elapsed.
@MainActor
final class TickScheduler {
    static let shared = TickScheduler()

    private struct Sub { let interval: TimeInterval; var last: Date; let action: @MainActor () -> Void }
    private var subs: [UUID: Sub] = [:]
    private var timer: Timer?
    private var tickLength: TimeInterval = 1

    func subscribe(every interval: TimeInterval, fireNow: Bool = true, action: @escaping @MainActor () -> Void) -> UUID {
        let id = UUID()
        subs[id] = Sub(interval: max(1, interval), last: Date(), action: action)
        if fireNow { action() }
        reschedule()
        return id
    }

    func unsubscribe(_ id: UUID) {
        subs[id] = nil
        reschedule()
    }

    private func reschedule() {
        let needed = subs.values.map(\.interval).min() ?? 0
        if subs.isEmpty {
            timer?.invalidate(); timer = nil; return
        }
        // Tick at 1s only if someone needs it; otherwise tick at the smallest interval (capped at 5s).
        let length = min(max(1, needed), 5)
        if timer != nil && length == tickLength { return }
        tickLength = length
        timer?.invalidate()
        let t = Timer(timeInterval: length, repeats: true) { _ in
            Task { @MainActor in TickScheduler.shared.fire() }
        }
        t.tolerance = length * 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func fire() {
        let now = Date()
        for (id, sub) in subs where now.timeIntervalSince(sub.last) >= sub.interval - tickLength * 0.5 {
            subs[id]?.last = now
            sub.action()
        }
    }
}

private struct RefreshModifier: ViewModifier {
    let interval: TimeInterval?
    let action: @MainActor () async -> Void
    @State private var token: UUID?

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard token == nil else { return }
                if let interval {
                    token = TickScheduler.shared.subscribe(every: interval) { Task { await action() } }
                } else {
                    Task { await action() }
                }
            }
            .onDisappear {
                if let token { TickScheduler.shared.unsubscribe(token) }
                token = nil
            }
    }
}

extension View {
    /// Runs `action` on appear and then every `interval` seconds while visible, via the shared coalesced timer.
    func refreshing(every interval: TimeInterval?, perform action: @escaping @MainActor () async -> Void) -> some View {
        modifier(RefreshModifier(interval: interval, action: action))
    }
}
