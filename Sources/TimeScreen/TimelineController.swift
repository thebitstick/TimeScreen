import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless windows refuse key status by default; the timeline needs the keyboard.
private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class TimelineController {
    static let shared = TimelineController()

    private var window: OverlayWindow?
    private var scrollMonitor: Any?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private let bridge = ScrubBridge()

    var isVisible: Bool { window != nil }
    var overlayWindow: NSWindow? { window }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard window == nil else { return }
        if Authenticator.shared.needsPrompt {
            Task {
                if await Authenticator.shared.unlock() { present() }
            }
        } else {
            present()
        }
    }

    private func present() {
        guard window == nil else { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else { return }

        let overlay = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        overlay.level = .popUpMenu
        overlay.isOpaque = true
        overlay.backgroundColor = .black
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        overlay.contentView = NSHostingView(rootView: TimelineWindow(recorder: .shared, bridge: bridge) { [weak self] in
            self?.hide()
        })
        overlay.setFrame(screen.frame, display: true)
        window = overlay
        Recorder.shared.setTimelineOpen(true)

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            nonisolated(unsafe) let scroll = event
            let consumed = MainActor.assumeIsolated { self?.handleScroll(scroll) ?? false }
            return consumed ? nil : event
        }
        // Esc closes the overlay no matter what has focus (the search field would otherwise swallow it).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            MainActor.assumeIsolated { self?.hide() }
            return nil
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }

        NSApp.activate(ignoringOtherApps: true)
        overlay.makeKeyAndOrderFront(nil)
    }

    func hide() {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        scrollMonitor = nil
        resignObserver = nil
        window?.orderOut(nil)
        window = nil
        Recorder.shared.setTimelineOpen(false)
        Authenticator.shared.timelineClosed()
        Thumbnails.clear()
    }

    /// The filmstrip is the widest-and-flattest scroll view in the window (the results list is tall).
    private static func findStrip(in view: NSView?) -> NSScrollView? {
        var best: (NSScrollView, CGFloat)?
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, let doc = scroll.documentView {
                let score = doc.frame.width - doc.frame.height
                if best == nil || score > best!.1 { best = (scroll, score) }
            }
            view.subviews.forEach(visit)
        }
        if let view { visit(view) }
        return best?.0
    }

    private func handleScroll(_ event: NSEvent) -> Bool {
        guard let window, event.window === window else { return false }
        if bridge.scrollView == nil { bridge.scrollView = Self.findStrip(in: window.contentView) }
        guard let strip = bridge.scrollView else { return false }
        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        let horizontal = abs(dx) > abs(dy)

        if !horizontal, let content = window.contentView,
           let hit = content.hitTest(content.convert(event.locationInWindow, from: nil)),
           let scrollView = hit.enclosingScrollView, scrollView !== strip {
            return false
        }

        var delta = horizontal ? dx : dy
        if !event.hasPreciseScrollingDeltas { delta *= 12 } // notched mouse wheels report whole lines
        let clip = strip.contentView
        let maxX = max(0, (strip.documentView?.frame.width ?? 0) - clip.bounds.width)
        let x = min(max(clip.bounds.origin.x - delta, 0), maxX)
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.origin.y))
        strip.reflectScrolledClipView(clip)
        return true
    }
}
