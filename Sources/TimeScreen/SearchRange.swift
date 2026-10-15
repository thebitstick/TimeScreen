import Foundation

enum SearchRange: String, CaseIterable, Identifiable {
    case anyTime, today, week, month, selectedDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyTime: String(localized: "Any time")
        case .today: String(localized: "Today")
        case .week: String(localized: "Past 7 days")
        case .month: String(localized: "Past 30 days")
        case .selectedDay: String(localized: "Selected day")
        }
    }

    func bounds(day: Date, now: Date = Date(), calendar: Calendar = .current) -> (from: Date?, to: Date?) {
        switch self {
        case .anyTime: return (nil, nil)
        case .today: return (calendar.startOfDay(for: now), nil)
        case .week: return (calendar.date(byAdding: .day, value: -7, to: now), nil)
        case .month: return (calendar.date(byAdding: .day, value: -30, to: now), nil)
        case .selectedDay:
            let start = calendar.startOfDay(for: day)
            return (start, calendar.date(byAdding: .day, value: 1, to: start))
        }
    }
}
