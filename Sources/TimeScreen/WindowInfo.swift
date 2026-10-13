import CoreGraphics
import Foundation

struct OnScreenWindow: Equatable {
    let pid: pid_t
    let owner: String
    let title: String
    let bounds: CGRect
}

enum Windows {
    static func frontToBack() -> [OnScreenWindow] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else { return nil }
            return OnScreenWindow(pid: pid, owner: info[kCGWindowOwnerName as String] as? String ?? "",
                                  title: info[kCGWindowName as String] as? String ?? "", bounds: bounds)
        }
    }

    static func topWindow(in windows: [OnScreenWindow], on display: CGRect) -> OnScreenWindow? {
        windows.first { window in
            window.bounds.width >= 200 && window.bounds.height >= 100
                && display.contains(CGPoint(x: window.bounds.midX, y: window.bounds.midY))
        }
    }

    static func isPrivate(title: String, keywords: [String]) -> Bool {
        keywords.contains { !$0.isEmpty && title.localizedCaseInsensitiveContains($0) }
    }
}
