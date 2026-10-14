import AppKit

/// A menu bar app that isn't in the Dock can't reliably bring its own windows to the front on recent macOS,
/// so it takes a Dock presence while a titled window (Settings, Welcome, an update prompt) is open.
@MainActor
enum DockPresence {
    private static var observing = false

    static func windowWillOpen() {
        observeClosings()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static var openSettingsAction: (() -> Void)?

    /// For code paths without a SettingsLink, such as the Welcome window's button.
    static func openSettings() {
        windowWillOpen()
        openSettingsAction?()
        frontOpenWindowsSoon()
    }

    /// The window of a SettingsLink or Sparkle prompt appears a moment after the click, once activation has passed.
    static func frontOpenWindowsSoon() {
        for delay in [0.15, 0.4, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                    bringToFront(window)
                }
            }
        }
    }

    static func bringToFront(_ window: NSWindow?) {
        windowWillOpen()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    static func windowDidFinish() {
        let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
        if !hasWindow { NSApp.setActivationPolicy(.accessory) }
    }

    private static func observeClosings() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let hasWindow = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) }
                    if !hasWindow { NSApp.setActivationPolicy(.accessory) }
                }
            }
        }
    }
}
