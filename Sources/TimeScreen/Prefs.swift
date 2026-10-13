import Foundation

enum Prefs {
    static let recording = "recording"
    static let interval = "interval"
    static let retentionDays = "retentionDays"
    static let ocr = "ocrEnabled"
    static let compactOld = "compactOld"
    static let allDisplays = "allDisplays"
    static let excludedApps = "excludedApps"
    static let hotkeyCode = "hotkeyCode"
    static let hotkeyMods = "hotkeyMods"
    static let hotkeyLabel = "hotkeyLabel"

    static let defaultExcluded = """
        com.1password.1password
        com.apple.keychainaccess
        com.apple.Passwords
        com.bitwarden.desktop
        """

    static func register() {
        UserDefaults.standard.register(defaults: [
            recording: true,
            interval: 5.0,
            retentionDays: 30,
            ocr: true,
            compactOld: true,
            allDisplays: true,
            excludedApps: defaultExcluded,
            hotkeyCode: 17,
            hotkeyMods: 2304, // ⌥⌘ (Carbon optionKey | cmdKey)
            hotkeyLabel: "T",
        ])
    }

    static func excludedBundleIDs() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: excludedApps) ?? ""
        return Set(raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }
}
