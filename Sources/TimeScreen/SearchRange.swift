import Foundation

enum SearchRange: String, CaseIterable, Identifiable {
    case anyTime, today, week, month, selectedDay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anyTime: "Any time"
        case .today: "Today"
        case .week: "Past 7 days"
        case .month: "Past 30 days"
        case .selectedDay: "Selected day"
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
