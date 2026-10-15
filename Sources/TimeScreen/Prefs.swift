import Foundation

enum Prefs {
    static let recording = "recording"
    static let interval = "interval"
    static let retentionDays = "retentionDays"
    static let maxStorageGB = "maxStorageGB"
    static let pauseOnBattery = "pauseOnBattery"
    static let backoffWhenAway = "backoffWhenAway"
    static let autoSummaries = "autoSummaries"
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
    static let pauseHotkeyCode = "pauseHotkeyCode"
    static let pauseHotkeyMods = "pauseHotkeyMods"
    static let pauseHotkeyLabel = "pauseHotkeyLabel"
    static let starHotkeyCode = "starHotkeyCode"
    static let starHotkeyMods = "starHotkeyMods"
    static let starHotkeyLabel = "starHotkeyLabel"

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
        Incógnito
        Navegación privada
        Navigation privée
        Inkognito
        Privater Modus
        Privénavigatie
        Privé browsen
        无痕
        隐身
        隐私浏览
        シークレット
        プライベートブラウズ
        プライベートブラウジング
        """

    static func register() {
        UserDefaults.standard.register(defaults: [
            recording: true,
            interval: 5.0,
            retentionDays: 30,
            maxStorageGB: 20,
            pauseOnBattery: false,
            backoffWhenAway: true,
            autoSummaries: true,
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
            pauseHotkeyCode: 0,
            pauseHotkeyMods: 0,
            pauseHotkeyLabel: "",
            starHotkeyCode: 0,
            starHotkeyMods: 0,
            starHotkeyLabel: "",
        ])
    }

    static func excludedBundleIDs() -> Set<String> {
        Set(ExcludedApps.parse(UserDefaults.standard.string(forKey: excludedApps) ?? ""))
    }
}

enum ExcludedApps {
    static func parse(_ raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func adding(_ bundleID: String, to raw: String) -> String {
        let current = parse(raw)
        return current.contains(bundleID) ? raw : (current + [bundleID]).joined(separator: "\n")
    }

    static func removing(_ bundleID: String, from raw: String) -> String {
        parse(raw).filter { $0 != bundleID }.joined(separator: "\n")
    }
}

extension Prefs {
    static func excludeApp(_ bundleID: String) {
        let current = UserDefaults.standard.string(forKey: excludedApps) ?? ""
        UserDefaults.standard.set(ExcludedApps.adding(bundleID, to: current), forKey: excludedApps)
    }

    static func privateTitleKeywords() -> [String] {
        let raw = UserDefaults.standard.string(forKey: privateTitles) ?? ""
        return raw.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
