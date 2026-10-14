import Foundation

enum Prefs {
    static let recording = "recording"
    static let interval = "interval"
    static let retentionDays = "retentionDays"
    static let maxStorageGB = "maxStorageGB"
    static let pauseOnBattery = "pauseOnBattery"
    static let pauseInLowPower = "pauseInLowPower"
    static let ocr = "ocrEnabled"
    static let compactOld = "compactOld"
    static let allDisplays = "allDisplays"
    static let scrollToOpen = "scrollToOpen"
    static let skipPrivate = "skipPrivate"
    static let welcomeShown = "welcomeShown"
    static let requireAuth = "requireAuth"
    static let authGrace = "authGrace"
    static let privateTitles = "privateTitles"
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

    static let defaultPrivateTitles = """
        Incognito
        InPrivate
        Private Browsing
        Private Window
        """

    static func register() {
        UserDefaults.standard.register(defaults: [
            recording: true,
            interval: 5.0,
            retentionDays: 30,
            maxStorageGB: 20,
            pauseOnBattery: false,
            pauseInLowPower: false,
            ocr: true,
            compactOld: true,
            allDisplays: true,
            scrollToOpen: true,
            skipPrivate: true,
            requireAuth: false,
            authGrace: 60.0,
            privateTitles: defaultPrivateTitles,
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

extension Prefs {
    static func excludeApp(_ bundleID: String) {
        guard !excludedBundleIDs().contains(bundleID) else { return }
        let current = UserDefaults.standard.string(forKey: excludedApps) ?? ""
        UserDefaults.standard.set(current.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + bundleID, forKey: excludedApps)
    }

    static func privateTitleKeywords() -> [String] {
        let raw = UserDefaults.standard.string(forKey: privateTitles) ?? ""
        return raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
