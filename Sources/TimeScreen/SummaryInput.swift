import Foundation

enum SummaryKind: String, CaseIterable {
    case frame, block, hour, day, app
}

struct SummaryRecord: Equatable {
    let kind: SummaryKind
    let key: String
    let start: Date
    let end: Date
    let text: String
    /// How many lower-level items it was built from. A rollup whose count has changed is stale.
    let inputs: Int
    let created: Date
}

/// A stretch of wall-clock time a summary covers, with the key it is cached under.
struct SummaryWindow: Equatable, Hashable {
    static let blockLength: TimeInterval = 15 * 60

    let kind: SummaryKind
    let start: Date
    let end: Date
    let key: String

    static func block(containing date: Date, calendar: Calendar = .current) -> SummaryWindow {
        let hour = calendar.dateInterval(of: .hour, for: date)?.start ?? date
        let offset = floor(date.timeIntervalSince(hour) / blockLength) * blockLength
        let start = hour.addingTimeInterval(offset)
        return SummaryWindow(kind: .block, start: start, end: start.addingTimeInterval(blockLength), key: format(start, "yyyy-MM-dd HH:mm", calendar))
    }

    static func hour(containing date: Date, calendar: Calendar = .current) -> SummaryWindow {
        let interval = calendar.dateInterval(of: .hour, for: date) ?? DateInterval(start: date, duration: 3600)
        return SummaryWindow(kind: .hour, start: interval.start, end: interval.end, key: format(interval.start, "yyyy-MM-dd HH", calendar))
    }

    static func day(containing date: Date, calendar: Calendar = .current) -> SummaryWindow {
        let interval = calendar.dateInterval(of: .day, for: date) ?? DateInterval(start: date, duration: 86_400)
        return SummaryWindow(kind: .day, start: interval.start, end: interval.end, key: format(interval.start, "yyyy-MM-dd", calendar))
    }

    static func app(_ app: String, on date: Date, calendar: Calendar = .current) -> SummaryWindow {
        let day = day(containing: date, calendar: calendar)
        return SummaryWindow(kind: .app, start: day.start, end: day.end, key: "\(day.key)|\(app)")
    }

    static func frame(_ frame: Frame) -> SummaryWindow {
        SummaryWindow(kind: .frame, start: frame.date, end: frame.date, key: String(frame.id))
    }

    func blocks(calendar: Calendar = .current) -> [SummaryWindow] {
        guard kind == .hour || kind == .day else { return [] }
        var result: [SummaryWindow] = []
        var cursor = start
        while cursor < end {
            result.append(Self.block(containing: cursor, calendar: calendar))
            cursor = cursor.addingTimeInterval(Self.blockLength)
        }
        return result
    }

    func hours(calendar: Calendar = .current) -> [SummaryWindow] {
        guard kind == .day else { return [] }
        var result: [SummaryWindow] = []
        var cursor = start
        while cursor < end {
            let hour = Self.hour(containing: cursor, calendar: calendar)
            result.append(hour)
            cursor = hour.end
        }
        return result
    }

    private static func format(_ date: Date, _ pattern: String, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

enum SummaryInput {
    /// Evenly spaced picks, keeping the first and the last, so a long stretch is represented from beginning to end.
    static func sample<T>(_ items: [T], limit: Int) -> [T] {
        guard items.count > limit, limit > 1 else { return limit <= 1 ? Array(items.prefix(max(limit, 0))) : items }
        return (0..<limit).map { items[$0 * (items.count - 1) / (limit - 1)] }
    }

    /// The lines worth reading from many screenshots of the same stretch: duplicates collapse to one, and lines that sit on
    /// most of the screenshots (menu bars, sidebars, the dock) are dropped, since they say nothing about what changed.
    static func condense(_ texts: [String], maxCharacters: Int) -> String {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for text in texts {
            var seenInThisFrame = Set<String>()
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.count >= 3, seenInThisFrame.insert(line).inserted else { continue }
                if counts[line] == nil { order.append(line) }
                counts[line, default: 0] += 1
            }
        }
        let chromeThreshold = Double(texts.count) * 0.6
        let interesting = texts.count >= 5 ? order.filter { Double(counts[$0] ?? 0) <= chromeThreshold } : order
        let lines = interesting.isEmpty ? order : interesting
        var out = ""
        for line in lines {
            if out.count + line.count + 1 > maxCharacters { break }
            out += line + "\n"
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func shorten(_ text: String, to characters: Int) -> String {
        text.count <= characters ? text : String(text.prefix(characters))
    }
}

enum SummaryPrompt {
    static let instructions = """
        You write short, factual summaries of what a person was doing on their Mac, using only text read from their screen \
        (it can be messy or incomplete). Write one or two short plain sentences with no lists, headings or markdown, in the second \
        person ("You read an email about…"). Say which apps or sites were involved and what the main subject was. Do not guess at \
        things the text does not show.
        """

    static let rollupInstructions = """
        You combine short notes about consecutive stretches of a person's time on their Mac into one brief summary. Write \
        plain prose in the second person ("You…") with no lists, headings or markdown, covering the main activities in order. Use only \
        what the notes say.
        """

    static func timeLabel(_ start: Date, _ end: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start))–\(formatter.string(from: end))"
    }

    static func frame(app: String, title: String, date: Date, text: String) -> String {
        var header = "App: \(app)"
        if !title.isEmpty { header += "\nWindow: \(title)" }
        header += "\nTime: \(date.formatted(date: .abbreviated, time: .shortened))"
        return "\(header)\n\nText on the screen:\n\(text)\n\nSummarize this."
    }

    static func stretch(label: String, apps: [(app: String, frames: Int)], text: String) -> String {
        let appLine = apps.sorted { $0.frames > $1.frames }.map { "\($0.app) (\($0.frames) screenshots)" }.joined(separator: ", ")
        return "Time: \(label)\nApps, most used first: \(appLine)\n\nText seen on the screen (repeated lines removed):\n\(text)\n\nSummarize what the person was doing."
    }

    static func rollup(title: String, notes: [(label: String, text: String)], maxSentences: Int) -> String {
        let lines = notes.map { "\($0.label): \($0.text)" }.joined(separator: "\n")
        return "\(title)\n\nNotes:\n\(lines)\n\nCombine these into one short summary of at most \(maxSentences) sentences."
    }

    static func appDay(app: String, day: String, text: String) -> String {
        "App: \(app)\nDay: \(day)\n\nText seen in this app across the day (repeated lines removed):\n\(text)\n\nSummarize what the person did in this app."
    }
}

struct SummaryOutputLanguage: Equatable {
    let name: String
    let example: String
    let rollupExample: String
}

enum SummaryLanguage {
    private static let examples: [String: (example: String, rollup: String)] = [
        "es": ("Leíste un correo sobre…", "Estuviste…"),
        "fr": ("Vous avez lu un e-mail sur…", "Vous avez…"),
        "de": ("Du hast eine E-Mail über … gelesen", "Du hast…"),
        "nl": ("Je las een e-mail over…", "Je…"),
        "it": ("Hai letto un'email su…", "Hai…"),
        "pt": ("Você leu um e-mail sobre…", "Você…"),
        "ko": ("이메일을 읽으셨습니다. 주제는…", "다음과 같은 활동을 하셨습니다…"),
        "zh-Hans": ("你阅读了一封关于……的邮件", "你……"),
        "zh-Hant": ("你閱讀了一封關於……的郵件", "你……"),
        "ja": ("あなたは…についてのメールを読みました", "あなたは…"),
    ]

    /// The language to ask the model to write in: the one the app is shown in, when the model supports it and it isn't English.
    /// The model follows the language of the example sentence more than a request, so each language brings its own example.
    static func output(for localization: String?, supports: (Locale) -> Bool) -> SummaryOutputLanguage? {
        guard let code = localization, supports(Locale(identifier: code)) else { return nil }
        let language = Locale.Language(identifier: code)
        guard let languageCode = language.languageCode?.identifier else { return nil }
        let key: String, name: String
        if languageCode == "zh" {
            let traditional = language.script?.identifier == "Hant" || ["TW", "HK", "MO"].contains(language.region?.identifier ?? "")
            key = traditional ? "zh-Hant" : "zh-Hans"
            name = traditional ? "Traditional Chinese" : "Simplified Chinese"
        } else {
            key = languageCode
            name = Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? languageCode
        }
        guard let sample = examples[key] else { return nil }
        return SummaryOutputLanguage(name: name, example: sample.example, rollupExample: sample.rollup)
    }

    static func instructions(_ base: String, for language: SummaryOutputLanguage?) -> String {
        guard let language else { return base }
        return "Always respond in \(language.name). "
            + base.replacingOccurrences(of: "\"You read an email about…\"", with: "\"\(language.example)\"")
                  .replacingOccurrences(of: "\"You…\"", with: "\"\(language.rollupExample)\"")
    }
}
