import AppKit
import LocalAuthentication

struct UnlockWindow {
    private var lastUnlockEnd = Date.distantPast

    func isOpen(grace: TimeInterval, now: Date = Date()) -> Bool {
        grace > 0 && now.timeIntervalSince(lastUnlockEnd) < grace
    }

    mutating func markUnlocked(at date: Date = Date()) { lastUnlockEnd = date }
    mutating func invalidate() { lastUnlockEnd = .distantPast }
}

@MainActor
final class Authenticator {
    static let shared = Authenticator()

    private var window = UnlockWindow()
    private var inProgress = false

    private init() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.window.invalidate() }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.window.invalidate() }
        }
    }

    var needsPrompt: Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Prefs.requireAuth) else { return false }
        return !window.isOpen(grace: defaults.double(forKey: Prefs.authGrace))
    }

    func timelineClosed() { window.markUnlocked() }

    func unlock() async -> Bool {
        guard needsPrompt else { return true }
        guard !inProgress else { return false }
        inProgress = true
        defer { inProgress = false }
        guard await Self.evaluate("Open your screen history") else { return false }
        window.markUnlocked()
        return true
    }

    static func evaluate(_ reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
