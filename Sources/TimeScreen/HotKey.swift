import AppKit
import Carbon.HIToolbox
import SwiftUI

struct HotKeySlot {
    let id: UInt32
    let codeKey: String
    let modsKey: String
    let labelKey: String
    let defaultCode: Int
    let defaultMods: Int
    let defaultLabel: String

    static let timeline = HotKeySlot(id: 1, codeKey: Prefs.hotkeyCode, modsKey: Prefs.hotkeyMods, labelKey: Prefs.hotkeyLabel,
                                     defaultCode: 17, defaultMods: 2304, defaultLabel: "T")
    static let pause = HotKeySlot(id: 2, codeKey: Prefs.pauseHotkeyCode, modsKey: Prefs.pauseHotkeyMods, labelKey: Prefs.pauseHotkeyLabel,
                                  defaultCode: 0, defaultMods: 0, defaultLabel: "")
}

/// A system-wide shortcut through Carbon's hot key API, which needs no extra permissions.
final class HotKey {
    static let timeline = HotKey(.timeline)
    static let pause = HotKey(.pause)

    private static var registry: [UInt32: HotKey] = [:]
    private static var handlerInstalled = false

    let slot: HotKeySlot
    var onPress: (() -> Void)?
    private var reference: EventHotKeyRef?

    private init(_ slot: HotKeySlot) {
        self.slot = slot
        Self.registry[slot.id] = self
    }

    func registerFromPrefs() {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: slot.modsKey) != 0 else { return unregister() }
        register(keyCode: UInt32(defaults.integer(forKey: slot.codeKey)), modifiers: UInt32(defaults.integer(forKey: slot.modsKey)))
    }

    func register(keyCode: UInt32, modifiers: UInt32) {
        unregister()
        Self.installHandlerOnce()
        RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x54534352), id: slot.id),
                            GetApplicationEventTarget(), 0, &reference)
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
    }

    private static func installHandlerOnce() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            DispatchQueue.main.async { HotKey.registry[identifier.id]?.onPress?() }
            return noErr
        }, 1, &spec, nil, nil)
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
    let hotkey: HotKey
    @AppStorage private var mods: Int
    @AppStorage private var label: String
    @State private var recording = false
    @State private var monitor: Any?

    init(hotkey: HotKey) {
        self.hotkey = hotkey
        _mods = AppStorage(wrappedValue: hotkey.slot.defaultMods, hotkey.slot.modsKey)
        _label = AppStorage(wrappedValue: hotkey.slot.defaultLabel, hotkey.slot.labelKey)
    }

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
            if !hotkey.slot.defaultLabel.isEmpty {
                Button("Restore Default") {
                    stop()
                    UserDefaults.standard.set(hotkey.slot.defaultCode, forKey: hotkey.slot.codeKey)
                    mods = hotkey.slot.defaultMods
                    label = hotkey.slot.defaultLabel
                    hotkey.register(keyCode: UInt32(hotkey.slot.defaultCode), modifiers: UInt32(hotkey.slot.defaultMods))
                }
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
        hotkey.unregister()
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let carbon = HotKey.carbonModifiers(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
            guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
            let key = event.charactersIgnoringModifiers?.uppercased() ?? ""
            UserDefaults.standard.set(Int(event.keyCode), forKey: hotkey.slot.codeKey)
            mods = Int(carbon)
            label = key == " " ? "Space" : key
            hotkey.register(keyCode: UInt32(event.keyCode), modifiers: carbon)
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
