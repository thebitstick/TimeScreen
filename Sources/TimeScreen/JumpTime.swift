import Foundation

enum JumpTime {
    private static let pattern = try! NSRegularExpression(pattern: #"^(\d{1,2})(?::?(\d{2}))?\s*(am?|pm?)?$"#)

    /// Without am/pm, an hour from 1 to 12 could be either half of the day, so both are returned.
    static func candidates(_ text: String, on day: Date, calendar: Calendar = .current) -> [Date] {
        let lowered = text.lowercased().replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        switch lowered {
        case "noon": return time(12, 0, on: day, calendar).map { [$0] } ?? []
        case "midnight": return time(0, 0, on: day, calendar).map { [$0] } ?? []
        default: break
        }
        let range = NSRange(lowered.startIndex..., in: lowered)
        guard let match = pattern.firstMatch(in: lowered, range: range) else { return [] }
        let group = { (i: Int) -> String? in Range(match.range(at: i), in: lowered).map { String(lowered[$0]) } }
        guard var hour = group(1).flatMap({ Int($0) }) else { return [] }
        let minute = group(2).flatMap { Int($0) } ?? 0
        guard (0...59).contains(minute) else { return [] }

        if let suffix = group(3) {
            guard (1...12).contains(hour) else { return [] }
            hour = hour % 12 + (suffix.hasPrefix("p") ? 12 : 0)
            return time(hour, minute, on: day, calendar).map { [$0] } ?? []
        }
        guard (0...23).contains(hour) else { return [] }
        if hour == 0 || hour > 12 { return time(hour, minute, on: day, calendar).map { [$0] } ?? [] }
        return [hour % 12, hour % 12 + 12].compactMap { time($0, minute, on: day, calendar) }
    }

    private static func time(_ hour: Int, _ minute: Int, on day: Date, _ calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }
}
