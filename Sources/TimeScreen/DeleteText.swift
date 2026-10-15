import Foundation

enum DeleteText {
    static func removal(count: Int, starred: Int) -> String {
        let base = String(localized: "\(count) screenshots and their search text will be removed. This can't be undone.")
        guard starred > 0 else { return base }
        return base + " " + String(localized: "\(starred) of them are starred, and starred screenshots go too.")
    }

    static func recentTitle(minutes: Int) -> String {
        minutes == 60 ? String(localized: "Delete the last hour?") : String(localized: "Delete the last \(minutes) minutes?")
    }

    static func recentEmpty(minutes: Int) -> String {
        minutes == 60 ? String(localized: "No screenshots were captured in the last hour.")
                      : String(localized: "No screenshots were captured in the last \(minutes) minutes.")
    }
}
