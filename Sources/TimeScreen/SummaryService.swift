import Foundation

protocol TextGenerator: Sendable {
    var contextSize: Int { get }
    func tokenCount(_ text: String) async -> Int
    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String
}

enum SummaryError: LocalizedError, Equatable {
    case noText
    case tooLong
    case empty
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noText: "There is no recognized text to summarize here."
        case .tooLong: "There was too much text to fit the model, even after trimming it."
        case .empty: "The model didn't return a summary."
        case .unavailable(let reason): reason
        case .failed(let reason): reason
        }
    }
}

/// A record with empty text means "looked, and there was no recognized text": it keeps a stretch of, say, a full-screen game from being
/// retried forever or from failing the hour and day built on top of it.
///
/// Builds and caches summaries from stored screen text: frames and app-days directly, 15-minute blocks from a sample of their
/// frames, and hours and days by combining the summaries below them. The model sees only text, one request at a time.
actor SummaryService {
    private let db: Database
    private let generator: TextGenerator
    private let calendar: Calendar

    /// Frames, blocks and apps get one or two sentences, so a short output limit keeps them quick.
    static let outputTokens = 110
    /// How much of the model's window the screen text may take. Reading the input is most of the time a request takes, and a longer
    /// input barely improves a short recap, so this is well under the window.
    static let inputTokens = 2000
    static let rollupOutputTokens = 280
    private static let framesPerBlock = 40
    private static let framesPerApp = 60

    init(db: Database, generator: TextGenerator, calendar: Calendar = .current) {
        self.db = db
        self.generator = generator
        self.calendar = calendar
    }

    func cached(_ window: SummaryWindow) async -> SummaryRecord? {
        (try? await db.summary(kind: window.kind, key: window.key)) ?? nil
    }

    /// How many model requests it would take to bring `window` (and everything under it) up to date.
    func pendingCount(_ window: SummaryWindow) async throws -> Int {
        switch window.kind {
        case .frame:
            return try await db.summary(kind: .frame, key: window.key) == nil ? 1 : 0
        case .block:
            let count = try await db.frames(from: window.start, to: window.end).count
            guard count > 0 else { return 0 }
            return try await db.summary(kind: .block, key: window.key)?.inputs == count ? 0 : 1
        case .app:
            return try await appFrames(window).isEmpty ? 0 : (try await isFreshApp(window) ? 0 : 1)
        case .hour, .day:
            let children = try await nonEmptyChildren(of: window)
            guard !children.isEmpty else { return 0 }
            var total = 0
            for child in children { total += try await pendingCount(child) }
            let fresh = try await db.summary(kind: window.kind, key: window.key)?.inputs == children.count
            return total + (total == 0 && fresh ? 0 : 1)
        }
    }

    func summarize(_ window: SummaryWindow, regenerate: Bool = false,
                   progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) async throws -> SummaryRecord? {
        let total = regenerate ? max(try await pendingCount(window), 1) : try await pendingCount(window)
        let run = Run(total: total, progress: progress)
        return try await summarize(window, regenerate: regenerate, run: run)
    }

    private final class Run: @unchecked Sendable {
        let total: Int
        var done = 0
        let progress: (@Sendable (Int, Int) -> Void)?
        init(total: Int, progress: (@Sendable (Int, Int) -> Void)?) { self.total = total; self.progress = progress }
        func step() { done += 1; progress?(min(done, total), total) }
    }

    private func summarize(_ window: SummaryWindow, regenerate: Bool, run: Run) async throws -> SummaryRecord? {
        try Task.checkCancellation()
        switch window.kind {
        case .frame: return try await frameSummary(window, regenerate: regenerate, run: run)
        case .block: return try await blockSummary(window, regenerate: regenerate, run: run)
        case .app: return try await appSummary(window, regenerate: regenerate, run: run)
        case .hour, .day: return try await rollupSummary(window, regenerate: regenerate, run: run)
        }
    }

    // MARK: Levels

    private func frameSummary(_ window: SummaryWindow, regenerate: Bool, run: Run) async throws -> SummaryRecord? {
        if !regenerate, let cached = try await db.summary(kind: .frame, key: window.key) { return cached }
        guard let id = Int64(window.key), let frame = try await db.frame(id: id) else { return nil }
        let text = (try await db.texts(for: [id]))[id] ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SummaryError.noText }
        let result = try await generate(instructions: SummaryPrompt.instructions) { characters in
            SummaryPrompt.frame(app: frame.app, title: frame.title, date: frame.date, text: SummaryInput.shorten(text, to: characters))
        }
        return try await store(window, text: result, inputs: 1, run: run)
    }

    private func blockSummary(_ window: SummaryWindow, regenerate: Bool, run: Run) async throws -> SummaryRecord? {
        let frames = try await db.frames(from: window.start, to: window.end)
        guard !frames.isEmpty else { return nil }
        if !regenerate, let cached = try await db.summary(kind: .block, key: window.key), cached.inputs == frames.count { return cached }
        let picked = SummaryInput.sample(frames, limit: Self.framesPerBlock)
        let texts = try await db.texts(for: picked.map(\.id))
        let ordered = picked.compactMap { texts[$0.id] }
        let apps = Dictionary(grouping: frames, by: \.app).map { (app: $0.key, frames: $0.value.count) }
        let label = SummaryPrompt.timeLabel(window.start, window.end)
        guard !SummaryInput.condense(ordered, maxCharacters: 100_000).isEmpty else {
            return try await store(window, text: "", inputs: frames.count, run: run)
        }
        let result = try await generate(instructions: SummaryPrompt.instructions) { characters in
            SummaryPrompt.stretch(label: label, apps: apps, text: SummaryInput.condense(ordered, maxCharacters: characters))
        }
        return try await store(window, text: result, inputs: frames.count, run: run)
    }

    private func appSummary(_ window: SummaryWindow, regenerate: Bool, run: Run) async throws -> SummaryRecord? {
        let frames = try await appFrames(window)
        guard !frames.isEmpty else { return nil }
        if !regenerate, try await isFreshApp(window) { return try await db.summary(kind: .app, key: window.key) }
        let picked = SummaryInput.sample(frames, limit: Self.framesPerApp)
        let texts = try await db.texts(for: picked.map(\.id))
        let ordered = picked.compactMap { texts[$0.id] }
        let name = frames[0].app
        let day = window.start.formatted(date: .complete, time: .omitted)
        guard !SummaryInput.condense(ordered, maxCharacters: 100_000).isEmpty else { throw SummaryError.noText }
        let result = try await generate(instructions: SummaryPrompt.instructions) { characters in
            SummaryPrompt.appDay(app: name, day: day, text: SummaryInput.condense(ordered, maxCharacters: characters))
        }
        return try await store(window, text: result, inputs: frames.count, run: run)
    }

    private func rollupSummary(_ window: SummaryWindow, regenerate: Bool, run: Run) async throws -> SummaryRecord? {
        let children = try await nonEmptyChildren(of: window)
        guard !children.isEmpty else { return nil }
        if !regenerate, let cached = try await db.summary(kind: window.kind, key: window.key),
           cached.inputs == children.count, try await pendingChildren(children) == 0 {
            return cached
        }
        var notes: [(label: String, text: String)] = []
        for child in children {
            if let record = try await summarize(child, regenerate: false, run: run), !record.text.isEmpty {
                notes.append((SummaryPrompt.timeLabel(child.start, child.end), record.text))
            }
        }
        guard !notes.isEmpty else { return try await store(window, text: "", inputs: children.count, run: run) }
        let title = window.kind == .hour
            ? "The hour starting \(window.start.formatted(date: .abbreviated, time: .shortened))"
            : window.start.formatted(date: .complete, time: .omitted)
        let result = try await generate(instructions: SummaryPrompt.rollupInstructions, outputTokens: Self.rollupOutputTokens) { _ in
            SummaryPrompt.rollup(title: title, notes: notes, maxSentences: window.kind == .hour ? 3 : 5)
        }
        return try await store(window, text: result, inputs: children.count, run: run)
    }

    // MARK: Helpers

    private func pendingChildren(_ children: [SummaryWindow]) async throws -> Int {
        var total = 0
        for child in children { total += try await pendingCount(child) }
        return total
    }

    private func nonEmptyChildren(of window: SummaryWindow) async throws -> [SummaryWindow] {
        let parts = window.kind == .hour ? window.blocks(calendar: calendar) : window.hours(calendar: calendar)
        var result: [SummaryWindow] = []
        for part in parts where try await !db.frames(from: part.start, to: part.end).isEmpty { result.append(part) }
        return result
    }

    private func appFrames(_ window: SummaryWindow) async throws -> [Frame] {
        let name = String(window.key.drop { $0 != "|" }.dropFirst())
        return try await db.frames(app: name, from: window.start, to: window.end)
    }

    private func isFreshApp(_ window: SummaryWindow) async throws -> Bool {
        try await db.summary(kind: .app, key: window.key)?.inputs == (try await appFrames(window).count)
    }

    private func store(_ window: SummaryWindow, text: String, inputs: Int, run: Run) async throws -> SummaryRecord {
        let record = SummaryRecord(kind: window.kind, key: window.key, start: window.start, end: window.end,
                                   text: text, inputs: inputs, created: Date())
        try await db.saveSummary(record)
        run.step()
        return record
    }

    /// Trims the prompt's text until the whole request fits the model's window, and again if the model still says it is too long.
    private func generate(instructions: String, outputTokens: Int = SummaryService.outputTokens,
                          build: (_ characters: Int) -> String) async throws -> String {
        let budget = min(max(generator.contextSize - outputTokens - 300, 100), Self.inputTokens)
        var characters = min(14_000, budget * 3)
        for _ in 0..<5 {
            let prompt = build(characters)
            let tokens = await generator.tokenCount(instructions + "\n" + prompt)
            if tokens > budget, characters > 400 {
                characters = max(400, Int(Double(characters) * min(0.85, Double(budget) / Double(tokens))))
                continue
            }
            do {
                return try Self.clean(try await generator.generate(instructions: instructions, prompt: prompt, maxTokens: outputTokens))
            } catch let error as SummaryError {
                throw error
            } catch {
                if Self.isContextOverflow(error), characters > 400 {
                    characters = max(400, Int(Double(characters) * 0.6))
                    continue
                }
                throw SummaryError.failed(error.localizedDescription)
            }
        }
        throw SummaryError.tooLong
    }

    static func isContextOverflow(_ error: Error) -> Bool {
        let description = String(describing: error).lowercased()
        return description.contains("contextsizeexceeded") || description.contains("exceededcontextwindowsize")
    }

    static func clean(_ text: String) throws -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Summary:", "summary:", "SUMMARY:"] where result.hasPrefix(prefix) {
            result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        result = result.replacingOccurrences(of: "\\s*\n\\s*", with: " ", options: .regularExpression)
        guard !result.isEmpty else { throw SummaryError.empty }
        return endingOnASentence(result)
    }

    /// When the model hits its length limit it stops mid-sentence; keep only the sentences that are complete.
    static func endingOnASentence(_ text: String) -> String {
        guard let last = text.last, !".!?\"')”’".contains(last) else { return text }
        guard let cut = text.lastIndex(where: { ".!?".contains($0) }) else { return text }
        let head = text[...cut]
        return head.count >= 20 ? String(head) : text
    }
}
