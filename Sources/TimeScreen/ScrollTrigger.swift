import AppKit

struct ScrollOpenGesture {
    var threshold: CGFloat = 6
    var idleReset: TimeInterval = 0.4
    var cooldown: TimeInterval = 1

    private var accumulated: CGFloat = 0
    private var lastEvent = Date.distantPast
    private var lastOpen = Date.distantPast

    mutating func shouldOpen(delta: CGFloat, flags: NSEvent.ModifierFlags, now: Date = Date()) -> Bool {
        guard flags.intersection(.deviceIndependentFlagsMask) == [.command, .shift] else {
            accumulated = 0
            return false
        }
        if now.timeIntervalSince(lastEvent) > idleReset { accumulated = 0 }
        lastEvent = now
        accumulated += abs(delta)
        guard accumulated >= threshold, now.timeIntervalSince(lastOpen) > cooldown else { return false }
        accumulated = 0
        lastOpen = now
        return true
    }
}

@MainActor
final class ScrollTrigger {
    static let shared = ScrollTrigger()

    private var monitor: Any?
    private var gesture = ScrollOpenGesture()

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let delta = event.scrollingDeltaX + event.scrollingDeltaY
            let flags = event.modifierFlags
            MainActor.assumeIsolated { self?.handle(delta: delta, flags: flags) }
        }
    }

    private func handle(delta: CGFloat, flags: NSEvent.ModifierFlags) {
        guard UserDefaults.standard.bool(forKey: Prefs.scrollToOpen) else { return }
        if gesture.shouldOpen(delta: delta, flags: flags) { TimelineController.shared.show() }
    }
}
