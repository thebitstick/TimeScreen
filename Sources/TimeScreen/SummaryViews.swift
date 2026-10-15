import SwiftUI

struct SummaryCard: View {
    let title: String
    var subtitle: String?
    let window: SummaryWindow
    let record: SummaryRecord?
    var pending = 0
    @ObservedObject var summarizer: Summarizer

    private var isWorking: Bool { summarizer.job?.window == window }
    private var busyElsewhere: Bool { summarizer.job != nil && !isWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.bold())
                Spacer()
                if !isWorking {
                    Button {
                        summarizer.start(window, title: title, regenerate: record != nil)
                    } label: {
                        record == nil ? Text("Summarize") : Text("Redo")
                    }
                    .buttonStyle(.plain).foregroundStyle(.tint)
                    .disabled(busyElsewhere)
                    .help(pending > 1 ? Text("Needs about \(pending) summaries: the smaller ones are written first.") : Text("Write this summary with on-device Apple Intelligence."))
                }
            }
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            if let job = summarizer.job, isWorking {
                ProgressView(value: Double(job.done), total: Double(max(job.total, 1)))
                HStack {
                    Group {
                        if job.total > 1 { Text("Writing… \(job.done) of \(job.total)") } else { Text("Writing…") }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { summarizer.cancel() }.buttonStyle(.plain).foregroundStyle(.tint).font(.caption)
                }
            } else if let error = summarizer.errors[window] {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            if let record, !record.text.isEmpty {
                Text(record.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if record != nil, !isWorking {
                Text("No text was recognized here, so there is nothing to summarize.").font(.caption).foregroundStyle(.secondary)
            } else if !isWorking, summarizer.errors[window] == nil {
                Group {
                    if pending > 1 { Text("Not written yet (about \(pending) summaries to write).") } else { Text("Not written yet.") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct SummaryPanel: View {
    let frame: Frame?
    let db: Database
    @ObservedObject var summarizer: Summarizer
    @State private var records: [SummaryWindow: SummaryRecord] = [:]
    @State private var pending: [SummaryWindow: Int] = [:]

    private struct LoadKey: Hashable {
        let frame: Int64?
        let revision: Int
    }

    private var cards: [(title: String, subtitle: String?, window: SummaryWindow)] {
        guard let frame else { return [] }
        let block = SummaryWindow.block(containing: frame.date)
        let hour = SummaryWindow.hour(containing: frame.date)
        let day = SummaryWindow.day(containing: frame.date)
        return [
            (String(localized: "This screenshot"), frame.date.formatted(date: .omitted, time: .standard), .frame(frame)),
            (String(localized: "Around this time"), SummaryPrompt.timeLabel(block.start, block.end), block),
            (String(localized: "This hour"), SummaryPrompt.timeLabel(hour.start, hour.end), hour),
            (String(localized: "This day"), frame.date.formatted(.dateTime.weekday(.wide).month().day()), day),
            (String(localized: "\(frame.app) today"), nil, .app(frame.app, on: frame.date)),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let message = summarizer.availability.message {
                    Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(cards, id: \.window) { card in
                    SummaryCard(title: card.title, subtitle: card.subtitle, window: card.window,
                                record: records[card.window], pending: pending[card.window] ?? 0, summarizer: summarizer)
                }
                if frame == nil { Text("Pick a screenshot to summarize.").foregroundStyle(.secondary) }
                Text("Written on this Mac by on-device Apple Intelligence from the text it read on your screen. Summaries can be wrong, so check the screenshot.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: LoadKey(frame: frame?.id, revision: summarizer.revision)) { await load() }
    }

    private func load() async {
        var loaded: [SummaryWindow: SummaryRecord] = [:]
        var counts: [SummaryWindow: Int] = [:]
        for card in cards {
            if let record = (try? await db.summary(kind: card.window.kind, key: card.window.key)) ?? nil { loaded[card.window] = record }
            if card.window.kind == .hour || card.window.kind == .day { counts[card.window] = await summarizer.pendingCount(card.window) }
        }
        records = loaded
        pending = counts
    }
}

struct DayRecapView: View {
    let day: Date
    let db: Database
    @ObservedObject var summarizer: Summarizer
    @State private var dayRecord: SummaryRecord?
    @State private var hours: [SummaryRecord] = []
    @State private var pending = 0

    private var window: SummaryWindow { .day(containing: day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recap of \(day.formatted(.dateTime.weekday(.wide).month().day()))").font(.headline)
                if let message = summarizer.availability.message {
                    Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SummaryCard(title: String(localized: "The day"), window: window, record: dayRecord, pending: pending, summarizer: summarizer)
                if hours.contains(where: { !$0.text.isEmpty }) {
                    Text("Hour by hour").font(.subheadline.bold())
                    ForEach(hours.filter { !$0.text.isEmpty }, id: \.key) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SummaryPrompt.timeLabel(record.start, record.end)).font(.caption).foregroundStyle(.secondary)
                            Text(record.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 400, height: 480)
        .task(id: summarizer.revision) { await load() }
    }

    private func load() async {
        dayRecord = (try? await db.summary(kind: .day, key: window.key)) ?? nil
        hours = (try? await db.summaries(kind: .hour, from: window.start, to: window.end)) ?? []
        pending = await summarizer.pendingCount(window)
    }
}
