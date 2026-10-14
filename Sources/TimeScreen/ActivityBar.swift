import SwiftUI

struct ActivityRun: Equatable {
    let app: String
    let start: TimeInterval
    let end: TimeInterval
}

enum Activity {
    static func runs(_ frames: [Frame], maxGap: TimeInterval = 300, tail: TimeInterval = 10) -> [ActivityRun] {
        var runs: [ActivityRun] = []
        var open: (app: String, start: TimeInterval, last: TimeInterval)?
        for frame in frames {
            let t = frame.date.timeIntervalSince1970
            if let current = open, current.app == frame.app, t - current.last <= maxGap {
                open = (current.app, current.start, t)
                continue
            }
            if let current = open {
                let end = t - current.last <= maxGap ? t : current.last + tail
                runs.append(ActivityRun(app: current.app, start: current.start, end: end))
            }
            open = (frame.app, t, t)
        }
        if let current = open { runs.append(ActivityRun(app: current.app, start: current.start, end: current.last + tail)) }
        return runs
    }

    static func initialDay(today: Date, daysWithFrames: [Date]) -> Date {
        if daysWithFrames.contains(today) { return today }
        return daysWithFrames.filter { $0 < today }.max() ?? today
    }

    /// Going back from inside a run lands on that run's first frame, so repeated presses walk backwards run by run.
    static func switchIndex(apps: [String], from index: Int, direction: Int) -> Int {
        guard apps.indices.contains(index) else { return index }
        var runStart = index
        while runStart > 0, apps[runStart - 1] == apps[index] { runStart -= 1 }
        if direction > 0 {
            var next = index
            while next < apps.count - 1, apps[next + 1] == apps[index] { next += 1 }
            return min(next + 1, apps.count - 1)
        }
        if index > runStart { return runStart }
        guard runStart > 0 else { return index }
        let previousApp = apps[runStart - 1]
        var previousStart = runStart - 1
        while previousStart > 0, apps[previousStart - 1] == previousApp { previousStart -= 1 }
        return previousStart
    }

    static func nearest(_ frames: [Frame], to t: TimeInterval) -> Int? {
        guard !frames.isEmpty else { return nil }
        var low = 0, high = frames.count - 1
        while low < high {
            let mid = (low + high) / 2
            if frames[mid].date.timeIntervalSince1970 < t { low = mid + 1 } else { high = mid }
        }
        if low > 0, abs(frames[low - 1].date.timeIntervalSince1970 - t) < abs(frames[low].date.timeIntervalSince1970 - t) { low -= 1 }
        return low
    }
}

struct ActivityBar: View {
    let frames: [Frame]
    let selectedID: Int64?
    let filter: String?
    let onSeek: (Int64) -> Void

    private let height: CGFloat = 30

    var body: some View {
        GeometryReader { geometry in
            let runs = Activity.runs(frames)
            let t0 = frames.first?.date.timeIntervalSince1970 ?? 0
            let t1 = max(runs.last?.end ?? t0 + 1, t0 + 1)
            let width = geometry.size.width
            let x = { (t: TimeInterval) in CGFloat((t - t0) / (t1 - t0)) * width }

            ZStack(alignment: .leading) {
                ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                    let left = x(run.start)
                    let runWidth = max(x(run.end) - left, 2)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(AppIcons.shared.color(for: run.app).opacity(filter == nil || filter == run.app ? 0.75 : 0.15))
                        if runWidth >= 28, let icon = AppIcons.shared.icon(for: run.app) {
                            Image(nsImage: icon).resizable().frame(width: 20, height: 20).padding(.leading, 4)
                        }
                    }
                    .frame(width: runWidth, height: height)
                    .offset(x: left)
                    .help(run.app)
                }
                if let frame = frames.first(where: { $0.id == selectedID }) {
                    Capsule().fill(.white).frame(width: 3, height: height + 8)
                        .shadow(color: .black.opacity(0.6), radius: 2)
                        .offset(x: x(frame.date.timeIntervalSince1970) - 1.5)
                }
            }
            .frame(width: width, height: height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let t = t0 + Double(min(max(value.location.x / width, 0), 1)) * (t1 - t0)
                let visible = filter.map { app in frames.filter { $0.app == app } } ?? frames
                if let i = Activity.nearest(visible, to: t), visible[i].id != selectedID { onSeek(visible[i].id) }
            })
        }
        .frame(height: height + 8)
    }
}

struct CalendarPopover: View {
    let days: [Date]
    @Binding var day: Date
    let onPick: () -> Void

    @State private var month: Date
    private let calendar = Calendar.current

    init(days: [Date], day: Binding<Date>, onPick: @escaping () -> Void) {
        self.days = days
        _day = day
        self.onPick = onPick
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: day.wrappedValue)?.start ?? day.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(!(earliest.map { month > $0 } ?? false))
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).fontWeight(.semibold)
                Spacer()
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!(latest.map { month < $0 } ?? false))
            }
            .buttonStyle(.plain)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 7), spacing: 2) {
                ForEach(Array(calendar.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol).font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    if let date = cell { dayButton(date) } else { Color.clear.frame(height: 30) }
                }
            }
        }
        .padding(14)
    }

    private func dayButton(_ date: Date) -> some View {
        let available = daySet.contains(date)
        let selected = calendar.isDate(date, inSameDayAs: day)
        return Button {
            day = date
            onPick()
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .frame(width: 30, height: 30)
                .background(selected ? Color.accentColor : .clear, in: Circle())
                .overlay { if calendar.isDateInToday(date), !selected { Circle().stroke(Color.accentColor, lineWidth: 1) } }
                .foregroundStyle(selected ? Color.white : available ? Color.primary : Color.secondary.opacity(0.4))
        }
        .buttonStyle(.plain)
        .disabled(!available)
    }

    private var daySet: Set<Date> { Set(days.map { calendar.startOfDay(for: $0) }) }
    private var earliest: Date? { days.min().flatMap { calendar.dateInterval(of: .month, for: $0)?.start } }
    private var latest: Date? { days.max().flatMap { calendar.dateInterval(of: .month, for: $0)?.start } }

    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: interval.start) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func shift(_ delta: Int) {
        month = calendar.date(byAdding: .month, value: delta, to: month) ?? month
    }
}
