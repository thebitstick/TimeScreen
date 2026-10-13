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

    func toggle() { isVisible ? hide() : show() }

    func show() {
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

final class HotKey {
    static let shared = HotKey()

    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?
    private var handlerInstalled = false

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    func registerFromPrefs() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Prefs.hotkeyMods) != 0 else { return unregister() }
        register(keyCode: UInt32(defaults.integer(forKey: Prefs.hotkeyCode)),
                 modifiers: UInt32(defaults.integer(forKey: Prefs.hotkeyMods)))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x54534352), id: 1)
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &reference)
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }

    static func describe(modifiers: UInt32, label: String) -> String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + label
    }
}

struct ShortcutRecorder: View {
    @AppStorage(Prefs.hotkeyMods) private var mods = 2304
    @AppStorage(Prefs.hotkeyLabel) private var label = "T"
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Button {
                recording ? stop() : start()
            } label: {
                Text(fieldText)
                    .foregroundStyle(recording || label.isEmpty ? .secondary : .primary)
                    .frame(width: 150, height: 22)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .stroke(recording ? Color.accentColor : Color.primary.opacity(0.2), lineWidth: recording ? 2 : 1))
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                if !label.isEmpty {
                    Button(action: clear) { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain)
                        .padding(.trailing, 5)
                        .help("Clear shortcut")
                }
            }
            Button("Restore Default") {
                stop()
                UserDefaults.standard.set(17, forKey: Prefs.hotkeyCode)
                mods = 2304
                label = "T"
                HotKey.shared.register(keyCode: 17, modifiers: 2304)
            }
        }
        .onDisappear(perform: stop)
    }

    private var fieldText: String {
        if recording { return "Type shortcut" }
        return label.isEmpty ? "None" : HotKey.describe(modifiers: UInt32(mods), label: label)
    }

    private func clear() {
        stop()
        mods = 0
        label = ""
        HotKey.shared.unregister()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let carbon = HotKey.carbonModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            UserDefaults.standard.set(Int(event.keyCode), forKey: Prefs.hotkeyCode)
            mods = Int(carbon)
            label = key == " " ? "Space" : key
            HotKey.shared.register(keyCode: UInt32(event.keyCode), modifiers: carbon)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
