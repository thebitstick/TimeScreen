import UniformTypeIdentifiers
import XCTest
@testable import TimeScreen

final class DatabaseTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        let path = NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite"
        return try Database(path: path)
    }

    func testFramesRememberTheirDisplay() async throws {
        let db = try makeDatabase()
        let now = Date()
        try await db.insert(date: now, app: "Safari", title: "", path: "a.jpg", text: "left screen words")
        try await db.insert(date: now, app: "Xcode", title: "", path: "a-d1.jpg", text: "right screen words", display: 1)
        let frames = try await db.frames(on: now)
        XCTAssertEqual(Set(frames.map(\.display)), [0, 1])
        let hits = try await db.search("right")
        XCTAssertEqual(hits.map(\.frame.display), [1])
    }

    func testPathsDoNotCollideAcrossDisplays() {
        let date = Date()
        XCTAssertNotEqual(Recorder.relativePath(for: date, display: 0, ext: "heic"), Recorder.relativePath(for: date, display: 1, ext: "heic"))
    }

    func testDeletingTheOldestFramesRemovesTheirIndexEntries() async throws {
        let db = try makeDatabase()
        let start = Date()
        for i in 0..<5 {
            try await db.insert(date: start.addingTimeInterval(Double(i)), app: "A", title: "", path: "\(i).jpg",
                                text: "shared word\(i)", boxes: WordBox.pack([WordBox(t: "x", x: 0, y: 0, w: 1, h: 1)]))
        }
        let oldest = try await db.oldestFrames(limit: 2)
        XCTAssertEqual(oldest.map(\.path), ["0.jpg", "1.jpg"])
        try await db.delete(ids: oldest.map(\.id))
        let left = try await db.frames(on: start)
        XCTAssertEqual(left.map(\.path), ["2.jpg", "3.jpg", "4.jpg"])
        let hits = try await db.search("shared")
        XCTAssertEqual(hits.count, 3)
        let boxes = try await db.boxes(for: oldest[0].id)
        XCTAssertNil(boxes)
    }

    func testSearchCanBeLimitedByDate() async throws {
        let db = try makeDatabase()
        let now = Date()
        try await db.insert(date: now.addingTimeInterval(-10 * 86_400), app: "Safari", title: "", path: "old.jpg", text: "budget notes")
        try await db.insert(date: now, app: "Safari", title: "", path: "new.jpg", text: "budget notes")
        let all = try await db.search("budget")
        XCTAssertEqual(all.count, 2)
        let recent = try await db.search("budget", from: now.addingTimeInterval(-86_400))
        XCTAssertEqual(recent.map(\.frame.path), ["new.jpg"])
        let before = try await db.search("budget", to: now.addingTimeInterval(-86_400))
        XCTAssertEqual(before.map(\.frame.path), ["old.jpg"])
        let apps = try await db.apps()
        XCTAssertEqual(apps.first?.app, "Safari")
        XCTAssertEqual(apps.first?.count, 2)
    }

    func testFramesCanBeListedByTimeRange() async throws {
        let db = try makeDatabase()
        let now = Date()
        for minutes in [30, 12, 8, 3, 1] {
            try await db.insert(date: now.addingTimeInterval(-Double(minutes) * 60), app: "A", title: "", path: "\(minutes).jpg", text: "words")
        }
        let recent = try await db.frames(from: now.addingTimeInterval(-10 * 60), to: now.addingTimeInterval(60))
        XCTAssertEqual(recent.map(\.path), ["8.jpg", "3.jpg", "1.jpg"])
        try await db.delete(ids: recent.map(\.id))
        let left = try await db.frames(on: now)
        XCTAssertEqual(left.map(\.path), ["30.jpg", "12.jpg"])
        let hits = try await db.search("words")
        XCTAssertEqual(hits.count, 2)
    }

    func testFramesCanBeListedByApp() async throws {
        let db = try makeDatabase()
        let now = Date()
        try await db.insert(date: now, app: "Mail", title: "", path: "a.jpg", text: "one")
        try await db.insert(date: now.addingTimeInterval(1), app: "Notes", title: "", path: "b.jpg", text: "two")
        try await db.insert(date: now.addingTimeInterval(2), app: "Mail", title: "", path: "c.jpg", text: "three")
        let mail = try await db.frames(app: "Mail")
        XCTAssertEqual(mail.map(\.path), ["a.jpg", "c.jpg"])
        let none = try await db.frames(app: "Music")
        XCTAssertTrue(none.isEmpty)
    }

    func testBundleIdentifiersAreStoredAndBackfilled() async throws {
        let db = try makeDatabase()
        let now = Date()
        try await db.insert(date: now, app: "Notes", title: "", path: "a.jpg", text: "one", bundle: "com.apple.Notes")
        try await db.insert(date: now.addingTimeInterval(1), app: "Mail", title: "", path: "b.jpg", text: "two")
        try await db.insert(date: now.addingTimeInterval(2), app: "Mail", title: "", path: "c.jpg", text: "three")
        let stored = try await db.frames(on: now)
        XCTAssertEqual(stored.map(\.bundle), ["com.apple.Notes", "", ""])
        let missing = try await db.appsMissingBundle()
        XCTAssertEqual(missing, ["Mail"])

        try await db.setBundle("com.apple.mail", forApp: "Mail")
        try await db.setBundle("com.example.other", forApp: "Notes")
        let after = try await db.frames(on: now)
        XCTAssertEqual(after.map(\.bundle), ["com.apple.Notes", "com.apple.mail", "com.apple.mail"])
        let pairs = try await db.appBundles()
        XCTAssertEqual(Set(pairs.map { "\($0.app)=\($0.bundle)" }), ["Notes=com.apple.Notes", "Mail=com.apple.mail"])
        let hits = try await db.search("two")
        XCTAssertEqual(hits.first?.frame.bundle, "com.apple.mail")
    }

    func testTextsCanBeFetchedForManyFrames() async throws {
        let db = try makeDatabase()
        var ids: [Int64] = []
        for i in 0..<450 {
            ids.append(try await db.insert(date: Date().addingTimeInterval(Double(i)), app: "A", title: "", path: "\(i).jpg", text: "frame number \(i)"))
        }
        let texts = try await db.texts(for: ids)
        XCTAssertEqual(texts.count, 450)
        XCTAssertEqual(texts[ids[0]], "frame number 0")
        XCTAssertEqual(texts[ids[449]], "frame number 449")
        let empty = try await db.texts(for: [])
        XCTAssertTrue(empty.isEmpty)
    }

    func testMatchExpression() {
        XCTAssertNil(Database.matchExpression("   "))
        XCTAssertEqual(Database.matchExpression("hello wor\"ld"), "\"hello\"* \"world\"*")
    }

    func testInsertSearchAndDays() async throws {
        let db = try makeDatabase()
        let now = Date()
        try await db.insert(date: now, app: "Safari", title: "Swift docs", path: "a.jpg", text: "Structured concurrency in Swift")
        try await db.insert(date: now.addingTimeInterval(5), app: "Xcode", title: "Main.swift", path: "b.jpg", text: "let greeting = hello")

        let hits = try await db.search("concurr swift")
        XCTAssertEqual(hits.map(\.frame.path), ["a.jpg"])
        let byApp = try await db.search("xcode")
        XCTAssertEqual(byApp.map(\.frame.path), ["b.jpg"])
        let inSafari = try await db.search("swift", app: "Safari")
        XCTAssertEqual(inSafari.map(\.frame.path), ["a.jpg"])
        let inXcode = try await db.search("swift", app: "Xcode")
        XCTAssertEqual(inXcode.map(\.frame.path), ["b.jpg"])
        let nowhere = try await db.search("swift", app: "Mail")
        XCTAssertTrue(nowhere.isEmpty)
        let none = try await db.search("nothing")
        XCTAssertTrue(none.isEmpty)

        let frames = try await db.frames(on: now)
        XCTAssertEqual(frames.map(\.path), ["a.jpg", "b.jpg"])
        let count = try await db.count(on: now)
        XCTAssertEqual(count, 2)
        let days = try await db.days()
        XCTAssertEqual(days, [Calendar.current.startOfDay(for: now)])
    }

    func testPruneRemovesRowsAndSearchEntries() async throws {
        let db = try makeDatabase()
        let old = Date().addingTimeInterval(-10 * 86_400)
        try await db.insert(date: old, app: "A", title: "", path: "old.jpg", text: "ancient words")
        try await db.insert(date: Date(), app: "A", title: "", path: "new.jpg", text: "fresh words")

        let removed = try await db.prune(before: Date().addingTimeInterval(-5 * 86_400))
        XCTAssertEqual(removed, ["old.jpg"])
        let hits = try await db.search("words")
        XCTAssertEqual(hits.map(\.frame.path), ["new.jpg"])
    }

    func testDeleteAll() async throws {
        let db = try makeDatabase()
        try await db.insert(date: Date(), app: "A", title: "", path: "x.jpg", text: "something")
        try await db.deleteAll()
        let hits = try await db.search("something")
        XCTAssertTrue(hits.isEmpty)
        let days = try await db.days()
        XCTAssertTrue(days.isEmpty)
    }
}

final class SignatureTests: XCTestCase {
    func testDuplicateDetection() {
        let base = [UInt8](repeating: 100, count: Signature.width * Signature.height)
        var tiny = base
        tiny[0] = 200
        XCTAssertTrue(Signature.isDuplicate(base, tiny))

        var changed = base
        for i in 0..<10 { changed[i] = 200 }
        XCTAssertFalse(Signature.isDuplicate(base, changed))
        XCTAssertFalse(Signature.isDuplicate(base, [1, 2, 3]))
    }

    func testRelativePathFormat() {
        let path = Recorder.relativePath(for: Date(), ext: "heic")
        XCTAssertNotNil(path.range(of: #"^\d{4}-\d{2}-\d{2}/\d{6}\.heic$"#, options: .regularExpression))
    }
}

final class WordBoxTests: XCTestCase {
    func testPackRoundTrip() {
        let words = [WordBox(t: "hello", x: 0.1234, y: 0.5, w: 0.2, h: 0.05), WordBox(t: "world", x: 0.4, y: 0.5, w: 0.2, h: 0.05)]
        let unpacked = WordBox.unpack(WordBox.pack(words))
        XCTAssertEqual(unpacked.map(\.t), ["hello", "world"])
        XCTAssertEqual(unpacked[0].x, 0.123, accuracy: 0.0005)
        XCTAssertTrue(WordBox.unpack(nil).isEmpty)
        XCTAssertNil(WordBox.pack([]))
    }

    func testTextReadsLinesTopToBottomAndLeftToRight() {
        let words = [
            WordBox(t: "world", x: 0.4, y: 0.80, w: 0.2, h: 0.05),
            WordBox(t: "second", x: 0.1, y: 0.50, w: 0.2, h: 0.05),
            WordBox(t: "hello", x: 0.1, y: 0.81, w: 0.2, h: 0.05),
        ]
        XCTAssertEqual(WordBox.text(of: words), "hello world\nsecond")
        XCTAssertEqual(WordBox.text(of: []), "")
    }

    func testRecasingRestoresTheOriginalCaseFromTheIndexedText() {
        let lowercase = ["hello", "world", "foo"].map { WordBox(t: $0, x: 0, y: 0, w: 1, h: 1) }
        let recased = WordBox.recased(lowercase, from: "Hello World,\nFoo")
        XCTAssertEqual(recased.map(\.t), ["Hello", "World", "Foo"])
        XCTAssertEqual(WordBox.recased(lowercase, from: "Hello World").map(\.t), ["hello", "world", "foo"])
        XCTAssertEqual(WordBox.recased(lowercase, from: "Hello There Foo").map(\.t), ["Hello", "world", "Foo"])
        XCTAssertTrue(WordBox.recased([], from: "").isEmpty)
    }

    func testMatchingIgnoresTheCaseOfStoredWords() {
        let boxes = [WordBox(t: "Anime", x: 0, y: 0, w: 1, h: 1), WordBox(t: "Folder", x: 0, y: 0, w: 1, h: 1)]
        XCTAssertEqual(WordBox.matches(boxes, terms: ["anim"]).map(\.t), ["Anime"])
    }

    func testMatches() {
        let boxes = [WordBox(t: "anime", x: 0, y: 0, w: 1, h: 1), WordBox(t: "folder", x: 0, y: 0, w: 1, h: 1)]
        XCTAssertEqual(WordBox.matches(boxes, terms: ["anim"]).map(\.t), ["anime"])
        XCTAssertTrue(WordBox.matches(boxes, terms: []).isEmpty)
    }

    func testBoxesStoredWithFrameAndPruned() async throws {
        let db = try Database(path: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite")
        let packed = WordBox.pack([WordBox(t: "hi", x: 0, y: 0, w: 0.1, h: 0.1)])
        let id = try await db.insert(date: Date().addingTimeInterval(-10 * 86_400), app: "A", title: "", path: "a.heic", text: "hi", boxes: packed)
        let stored = try await db.boxes(for: id)
        XCTAssertEqual(WordBox.unpack(stored).map(\.t), ["hi"])
        _ = try await db.prune(before: Date())
        let afterPrune = try await db.boxes(for: id)
        XCTAssertNil(afterPrune)
    }

    func testCompactionCandidates() async throws {
        let db = try Database(path: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite")
        let old = try await db.insert(date: Date().addingTimeInterval(-3 * 86_400), app: "A", title: "", path: "old.jpg", text: "")
        try await db.insert(date: Date(), app: "A", title: "", path: "new.heic", text: "")
        var due = try await db.framesToCompact(before: Date().addingTimeInterval(-86_400), limit: 10)
        XCTAssertEqual(due.map(\.path), ["old.jpg"])
        try await db.markCompacted(id: old, path: "old.heic")
        due = try await db.framesToCompact(before: Date().addingTimeInterval(-86_400), limit: 10)
        XCTAssertTrue(due.isEmpty)
        let frames = try await db.frames(on: Date().addingTimeInterval(-3 * 86_400))
        XCTAssertEqual(frames.map(\.path), ["old.heic"])
    }
}

final class CompactionTests: XCTestCase {
    func testEncodeThenDownscale() throws {
        let context = CGContext(data: nil, width: 2000, height: 1000, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2000, height: 1000))
        let image = context.makeImage()!

        let (data, ext) = try Capturer.encode(image)
        XCTAssertTrue(["heic", "jpg"].contains(ext))
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).\(ext)")
        try data.write(to: url)

        let small = try XCTUnwrap(Thumbnails.downscaled(url, maxPixel: 1000))
        XCTAssertEqual(small.width, 1000)
        XCTAssertEqual(small.height, 500)
        XCTAssertEqual(try XCTUnwrap(Thumbnails.downscaled(url, maxPixel: 4000)).width, 2000)
    }
}

final class ScrollOpenGestureTests: XCTestCase {
    func testOpensOnlyWithCommandShiftAndEnoughScrolling() {
        var gesture = ScrollOpenGesture()
        let start = Date()
        XCTAssertFalse(gesture.shouldOpen(delta: 20, flags: [.command], now: start))
        XCTAssertFalse(gesture.shouldOpen(delta: 20, flags: [.command, .shift, .option], now: start))
        XCTAssertFalse(gesture.shouldOpen(delta: 2, flags: [.command, .shift], now: start))
        XCTAssertTrue(gesture.shouldOpen(delta: 5, flags: [.command, .shift], now: start.addingTimeInterval(0.1)))
    }

    func testDoesNotReopenDuringCooldownAndForgetsIdleScrolling() {
        var gesture = ScrollOpenGesture()
        let start = Date()
        XCTAssertTrue(gesture.shouldOpen(delta: 10, flags: [.command, .shift], now: start))
        XCTAssertFalse(gesture.shouldOpen(delta: 10, flags: [.command, .shift], now: start.addingTimeInterval(0.5)))
        XCTAssertTrue(gesture.shouldOpen(delta: 10, flags: [.command, .shift], now: start.addingTimeInterval(2)))
        var idle = ScrollOpenGesture()
        XCTAssertFalse(idle.shouldOpen(delta: 4, flags: [.command, .shift], now: start))
        XCTAssertFalse(idle.shouldOpen(delta: 4, flags: [.command, .shift], now: start.addingTimeInterval(5)))
    }
}

final class WindowInfoTests: XCTestCase {
    private func window(_ owner: String, _ title: String, _ bounds: CGRect) -> OnScreenWindow {
        OnScreenWindow(pid: 1, owner: owner, title: title, bounds: bounds)
    }

    func testTopWindowIsTheFrontmostOneCenteredOnTheDisplay() {
        let left = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windows = [
            window("Mail", "Inbox", CGRect(x: 2000, y: 100, width: 800, height: 600)),
            window("Xcode", "Main.swift", CGRect(x: 100, y: 100, width: 800, height: 600)),
            window("Safari", "Docs", CGRect(x: 50, y: 50, width: 800, height: 600)),
        ]
        XCTAssertEqual(Windows.topWindow(in: windows, on: left)?.owner, "Xcode")
        XCTAssertEqual(Windows.topWindow(in: windows, on: CGRect(x: 1920, y: 0, width: 1920, height: 1080))?.owner, "Mail")
        XCTAssertNil(Windows.topWindow(in: windows, on: CGRect(x: 5000, y: 0, width: 100, height: 100)))
    }

    func testTinyWindowsAreIgnored() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windows = [window("Widget", "", CGRect(x: 10, y: 10, width: 60, height: 40)),
                       window("Notes", "Todo", CGRect(x: 100, y: 100, width: 500, height: 400))]
        XCTAssertEqual(Windows.topWindow(in: windows, on: display)?.owner, "Notes")
    }

    func testAPrivateWindowBehindATitlelessPopupStillCounts() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let windows = [window("Zen", "", CGRect(x: 100, y: 100, width: 300, height: 200)),
                       window("Zen", "Speedtest — Private Browsing", CGRect(x: 0, y: 0, width: 1200, height: 800)),
                       window("Zen", "Elsewhere — Private Browsing", CGRect(x: 3000, y: 0, width: 1200, height: 800))]
        XCTAssertTrue(Windows.showsPrivateWindow(windows, on: display, keywords: ["Private Browsing"]))
        XCTAssertFalse(Windows.showsPrivateWindow(Array(windows.prefix(1)), on: display, keywords: ["Private Browsing"]))
        XCTAssertTrue(Windows.showsPrivateWindow(windows, on: CGRect(x: 1920, y: 0, width: 1920, height: 1080), keywords: ["Private Browsing"]))
        XCTAssertFalse(Windows.showsPrivateWindow(windows, on: CGRect(x: 5000, y: 0, width: 1920, height: 1080), keywords: ["Private Browsing"]))
    }

    func testTitleFallsBackToAnotherWindowOfTheSameApp() {
        let display = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let popup = window("Zen", "", CGRect(x: 100, y: 100, width: 300, height: 200))
        let page = window("Zen", "Docs", CGRect(x: 0, y: 0, width: 1200, height: 800))
        XCTAssertEqual(Windows.title(of: popup, in: [popup, page], on: display), "Docs")
    }

    func testPrivateTitlesMatchCaseInsensitively() {
        let keywords = ["Incognito", "Private Browsing"]
        XCTAssertTrue(Windows.isPrivate(title: "New Tab - Google Chrome (incognito)", keywords: keywords))
        XCTAssertTrue(Windows.isPrivate(title: "Docs — Private Browsing", keywords: keywords))
        XCTAssertFalse(Windows.isPrivate(title: "Docs", keywords: keywords))
        XCTAssertFalse(Windows.isPrivate(title: "Docs", keywords: [""]))
    }
}

final class SearchRangeTests: XCTestCase {
    func testBounds() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = calendar.startOfDay(for: now.addingTimeInterval(-5 * 86_400))
        XCTAssertNil(SearchRange.anyTime.bounds(day: day, now: now, calendar: calendar).from)
        XCTAssertEqual(SearchRange.today.bounds(day: day, now: now, calendar: calendar).from, calendar.startOfDay(for: now))
        XCTAssertEqual(SearchRange.week.bounds(day: day, now: now, calendar: calendar).from, now.addingTimeInterval(-7 * 86_400))
        let selected = SearchRange.selectedDay.bounds(day: day, now: now, calendar: calendar)
        XCTAssertEqual(selected.from, day)
        XCTAssertEqual(selected.to, day.addingTimeInterval(86_400))
    }
}

final class JumpTimeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private lazy var day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13))!

    private func hours(_ text: String) -> [String] {
        JumpTime.candidates(text, on: day, calendar: calendar).map { calendar.dateComponents([.hour, .minute], from: $0) }
            .map { String(format: "%02d:%02d", $0.hour!, $0.minute!) }
    }

    func testExplicitTimes() {
        XCTAssertEqual(hours("3:45pm"), ["15:45"])
        XCTAssertEqual(hours("3:45 PM"), ["15:45"])
        XCTAssertEqual(hours("12am"), ["00:00"])
        XCTAssertEqual(hours("12pm"), ["12:00"])
        XCTAssertEqual(hours("9 a"), ["09:00"])
        XCTAssertEqual(hours("15:30"), ["15:30"])
        XCTAssertEqual(hours("1530"), ["15:30"])
        XCTAssertEqual(hours("noon"), ["12:00"])
        XCTAssertEqual(hours("midnight"), ["00:00"])
    }

    func testAmbiguousHoursOfferBothHalvesOfTheDay() {
        XCTAssertEqual(hours("3:45"), ["03:45", "15:45"])
        XCTAssertEqual(hours("345"), ["03:45", "15:45"])
        XCTAssertEqual(hours("12:10"), ["00:10", "12:10"])
        XCTAssertEqual(hours("9"), ["09:00", "21:00"])
    }

    func testNonsenseIsRejected() {
        for text in ["", "abc", "25:00", "13pm", "3:75", "0pm", "3:4"] { XCTAssertEqual(hours(text), [], text) }
    }
}

final class StorageCapTests: XCTestCase {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("timescreen-cap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func fill(_ db: Database, root: URL, days: Int, perDay: Int, bytes: Int) async throws {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-Double(days) * 86_400)
        for day in 0..<days {
            for n in 0..<perDay {
                let date = start.addingTimeInterval(Double(day) * 86_400 + Double(n) * 60)
                let path = Recorder.relativePath(for: date, ext: "heic")
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(repeating: 7, count: bytes).write(to: url)
                try await db.insert(date: date, app: "A", title: "", path: path, text: "frame \(day)-\(n)",
                                    boxes: WordBox.pack([WordBox(t: "x", x: 0, y: 0, w: 1, h: 1)]))
            }
        }
    }

    func testDeletesTheOldestFramesDownToNinetyPercentOfTheCap() async throws {
        let root = try makeRoot()
        let db = try Database(path: root.appendingPathComponent("index.sqlite").path)
        let frames = root.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try await fill(db, root: frames, days: 3, perDay: 10, bytes: 64 * 1024)
        let before = await Storage.usage(of: frames)
        let cap = before * 6 / 10
        let everything = try await db.oldestFrames(limit: 1000)

        let removed = await Storage.enforce(cap: cap, root: frames, db: db)
        XCTAssertTrue(removed)

        let after = await Storage.usage(of: frames)
        XCTAssertLessThanOrEqual(after, Int64(Double(cap) * 0.9))
        XCTAssertGreaterThan(after, 0)

        let remaining = try await db.oldestFrames(limit: 1000)
        XCTAssertLessThan(remaining.count, 30)
        XCTAssertGreaterThan(remaining.count, 0)
        XCTAssertEqual(remaining.map(\.date), remaining.map(\.date).sorted())
        for frame in remaining { XCTAssertTrue(FileManager.default.fileExists(atPath: frames.appendingPathComponent(frame.path).path)) }

        let all = try await db.search("frame", limit: 1000)
        XCTAssertEqual(all.count, remaining.count)
        XCTAssertEqual(remaining.map(\.id), everything.suffix(remaining.count).map(\.id))
        let files = try FileManager.default.subpathsOfDirectory(atPath: frames.path).filter { $0.hasSuffix(".heic") }
        XCTAssertEqual(files.count, remaining.count)
    }

    func testNothingIsDeletedUnderTheCap() async throws {
        let root = try makeRoot()
        let db = try Database(path: root.appendingPathComponent("index.sqlite").path)
        let frames = root.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try await fill(db, root: frames, days: 1, perDay: 5, bytes: 32 * 1024)
        let removed = await Storage.enforce(cap: 10_000_000, root: frames, db: db)
        XCTAssertFalse(removed)
        let remaining = try await db.oldestFrames(limit: 100)
        XCTAssertEqual(remaining.count, 5)
    }

    func testEmptyDayFoldersAreRemoved() async throws {
        let root = try makeRoot()
        let db = try Database(path: root.appendingPathComponent("index.sqlite").path)
        let frames = root.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        try await fill(db, root: frames, days: 3, perDay: 4, bytes: 64 * 1024)
        let before = await Storage.usage(of: frames)
        _ = await Storage.enforce(cap: before / 3, root: frames, db: db)
        let folders = try FileManager.default.contentsOfDirectory(atPath: frames.path)
        for folder in folders {
            let inside = try FileManager.default.contentsOfDirectory(atPath: frames.appendingPathComponent(folder).path)
            XCTAssertFalse(inside.isEmpty, "\(folder) should not be left empty")
        }
    }
}

final class UnlockWindowTests: XCTestCase {
    func testStaysOpenOnlyWithinTheGracePeriod() {
        var window = UnlockWindow()
        let start = Date()
        XCTAssertFalse(window.isOpen(grace: 60, now: start))
        window.markUnlocked(at: start)
        XCTAssertTrue(window.isOpen(grace: 60, now: start.addingTimeInterval(30)))
        XCTAssertFalse(window.isOpen(grace: 60, now: start.addingTimeInterval(61)))
    }

    func testEveryTimeAlwaysAsks() {
        var window = UnlockWindow()
        let start = Date()
        window.markUnlocked(at: start)
        XCTAssertFalse(window.isOpen(grace: 0, now: start))
    }

    func testInvalidatingForcesAnotherPrompt() {
        var window = UnlockWindow()
        let start = Date()
        window.markUnlocked(at: start)
        window.invalidate()
        XCTAssertFalse(window.isOpen(grace: 900, now: start))
    }
}

final class MenuBarStateTests: XCTestCase {
    private func symbol(_ permission: Bool, _ recording: Bool, _ skip: SkipReason?, _ error: Bool) -> String {
        MenuBarState.symbol(hasPermission: permission, isRecording: recording, skip: skip, hasError: error)
    }

    func testSymbolFollowsTheMostImportantState() {
        XCTAssertEqual(symbol(true, true, nil, false), "record.circle")
        XCTAssertEqual(symbol(true, false, nil, false), "pause.circle")
        XCTAssertEqual(symbol(true, true, .privateWindow, false), "eye.slash.circle")
        XCTAssertEqual(symbol(true, true, .onBattery, false), "bolt.slash.circle")
        XCTAssertEqual(symbol(true, true, .diskAlmostFull, false), "externaldrive.badge.exclamationmark")
        XCTAssertEqual(symbol(true, true, nil, true), "exclamationmark.circle")
        XCTAssertEqual(symbol(false, true, nil, false), "exclamationmark.triangle")
        XCTAssertEqual(symbol(false, false, .privateWindow, true), "exclamationmark.triangle")
        XCTAssertEqual(symbol(true, false, .privateWindow, true), "pause.circle")
    }

    func testEveryStateHasADistinctDescription() {
        let descriptions = [
            MenuBarState.description(hasPermission: true, isRecording: true, skip: nil, hasError: false),
            MenuBarState.description(hasPermission: true, isRecording: false, skip: nil, hasError: false),
            MenuBarState.description(hasPermission: true, isRecording: true, skip: .privateWindow, hasError: false),
            MenuBarState.description(hasPermission: true, isRecording: true, skip: .onBattery, hasError: false),
            MenuBarState.description(hasPermission: true, isRecording: true, skip: .lowPowerMode, hasError: false),
            MenuBarState.description(hasPermission: true, isRecording: true, skip: .diskAlmostFull, hasError: false),
            MenuBarState.description(hasPermission: true, isRecording: true, skip: nil, hasError: true),
            MenuBarState.description(hasPermission: false, isRecording: true, skip: nil, hasError: false),
        ]
        XCTAssertEqual(Set(descriptions).count, descriptions.count)
    }
}

final class SkipReasonTests: XCTestCase {
    func testPowerSettingsOnlyApplyWhenEnabled() {
        XCTAssertNil(SkipReason.power(onBattery: true, lowPower: true, pauseOnBattery: false, pauseInLowPower: false))
        XCTAssertEqual(SkipReason.power(onBattery: true, lowPower: false, pauseOnBattery: true, pauseInLowPower: false), .onBattery)
        XCTAssertNil(SkipReason.power(onBattery: false, lowPower: false, pauseOnBattery: true, pauseInLowPower: true))
        XCTAssertEqual(SkipReason.power(onBattery: false, lowPower: true, pauseOnBattery: false, pauseInLowPower: true), .lowPowerMode)
        XCTAssertEqual(SkipReason.power(onBattery: true, lowPower: true, pauseOnBattery: true, pauseInLowPower: true), .lowPowerMode)
    }

    func testDiskThreshold() {
        XCTAssertEqual(SkipReason.disk(freeBytes: 500_000_000), .diskAlmostFull)
        XCTAssertNil(SkipReason.disk(freeBytes: 5_000_000_000))
        XCTAssertNil(SkipReason.disk(freeBytes: 1_000_000_000))
        XCTAssertGreaterThan(Disk.freeBytes(at: FileManager.default.temporaryDirectory), 0)
    }
}

final class ExcludeAppTests: XCTestCase {
    func testExcludingAnAppAppendsItOnceAndKeepsTheRest() {
        let key = Prefs.excludedApps
        let saved = UserDefaults.standard.object(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.set("com.example.one\n", forKey: key)
        Prefs.excludeApp("com.example.two")
        Prefs.excludeApp("com.example.two")
        XCTAssertEqual(Prefs.excludedBundleIDs(), ["com.example.one", "com.example.two"])
    }
}

@MainActor
final class ExportTests: XCTestCase {
    private func makeFrames() -> [Frame] {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 9, minute: 30, second: 5))!
        return [Frame(id: 1, date: start, app: "Mail", title: "Inbox", path: "a.heic"),
                Frame(id: 2, date: start.addingTimeInterval(60), app: "Notes", title: "", path: "b.heic", display: 1)]
    }

    func testFileNamesKeepTheDisplay() {
        let frames = makeFrames()
        XCTAssertEqual(Transcript.fileName(for: frames[0], ext: "heic"), "093005.heic")
        XCTAssertEqual(Transcript.fileName(for: frames[1], ext: "jpg"), "093105-d1.jpg")
    }

    func testMarkdownTranscript() {
        let md = Transcript.markdown(title: "Day", frames: makeFrames(), texts: [1: "Hello\nworld", 2: "  "])
        XCTAssertTrue(md.hasPrefix("# Day\n"))
        XCTAssertTrue(md.contains("## 2026-10-13 09:30:05 · Mail — Inbox\n\n> Hello\n> world\n"))
        XCTAssertTrue(md.contains("## 2026-10-13 09:31:05 · Notes (display 2)\n"))
        XCTAssertFalse(md.contains("> \n"))
    }

    private func makeImage(_ url: URL, as format: ExportFormat) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, rep.cgImage!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try (data as Data).write(to: url)
    }

    private func kind(_ url: URL) throws -> String {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return CGImageSourceGetType(source) as String? ?? ""
    }

    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ts-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testAnImageInTheChosenFormatIsCopiedUntouched() throws {
        let dir = try scratch()
        let source = dir.appendingPathComponent("in.heic")
        try makeImage(source, as: .highEfficiency)
        let copy = dir.appendingPathComponent("out.heic")
        try ImageEncoding.write(source, as: .highEfficiency, to: copy)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: source))
    }

    func testImagesAreConvertedBetweenTheTwoFormats() throws {
        let dir = try scratch()
        let heic = dir.appendingPathComponent("in.heic")
        try makeImage(heic, as: .highEfficiency)
        let jpeg = dir.appendingPathComponent("out.jpg")
        try ImageEncoding.write(heic, as: .mostCompatible, to: jpeg)
        XCTAssertEqual(try kind(jpeg), UTType.jpeg.identifier)

        let back = dir.appendingPathComponent("back.heic")
        try ImageEncoding.write(jpeg, as: .highEfficiency, to: back)
        XCTAssertEqual(try kind(back), UTType.heic.identifier)

        let png = dir.appendingPathComponent("out.png")
        try ImageEncoding.write(heic, as: .bestQuality, to: png)
        XCTAssertEqual(try kind(png), UTType.png.identifier)
        XCTAssertEqual(try Data(contentsOf: png).prefix(4), Data([0x89, 0x50, 0x4E, 0x47]))
    }

    func testPNGIsLosslessOnceItIsPNG() throws {
        let dir = try scratch()
        let png = dir.appendingPathComponent("in.png")
        try makeImage(png, as: .bestQuality)
        let copy = dir.appendingPathComponent("out.png")
        try ImageEncoding.write(png, as: .bestQuality, to: copy)
        XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: png))
    }

    func testFormatsKnowTheirFiles() {
        XCTAssertTrue(ExportFormat.mostCompatible.matches(URL(fileURLWithPath: "/x/a.JPG")))
        XCTAssertTrue(ExportFormat.mostCompatible.matches(URL(fileURLWithPath: "/x/a.jpeg")))
        XCTAssertFalse(ExportFormat.mostCompatible.matches(URL(fileURLWithPath: "/x/a.heic")))
        XCTAssertTrue(ExportFormat.highEfficiency.matches(URL(fileURLWithPath: "/x/a.heic")))
        XCTAssertEqual(ExportFormat.mostCompatible.fileExtension, "jpg")
        XCTAssertEqual(ExportFormat.highEfficiency.fileExtension, "heic")
        XCTAssertTrue(ExportFormat.bestQuality.matches(URL(fileURLWithPath: "/x/a.PNG")))
        XCTAssertFalse(ExportFormat.bestQuality.matches(URL(fileURLWithPath: "/x/a.jpg")))
        XCTAssertEqual(ExportFormat.bestQuality.fileExtension, "png")
        XCTAssertNil(ExportFormat.bestQuality.quality)
        XCTAssertEqual(ExportFormat.allCases.count, 3)
    }

    func testWritingADayUsesTheChosenFormatAndAddsATranscript() throws {
        let root = try scratch()
        let frames = makeFrames()
        try makeImage(root.appendingPathComponent(frames[0].path), as: .highEfficiency)
        try makeImage(root.appendingPathComponent(frames[1].path), as: .highEfficiency)

        let compatible = root.appendingPathComponent("compatible")
        try Exporter.writeDay(frames: frames, texts: [1: "Hello"], title: "Day", root: root, format: .mostCompatible, into: compatible)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: compatible.path).sorted(), ["093005.jpg", "093105-d1.jpg", "transcript.md"])
        XCTAssertEqual(try kind(compatible.appendingPathComponent("093005.jpg")), UTType.jpeg.identifier)

        let efficient = root.appendingPathComponent("efficient")
        try Exporter.writeDay(frames: frames, texts: [1: "Hello"], title: "Day", root: root, format: .highEfficiency, into: efficient)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: efficient.path).sorted(), ["093005.heic", "093105-d1.heic", "transcript.md"])
        let transcript = try String(contentsOf: efficient.appendingPathComponent("transcript.md"), encoding: .utf8)
        XCTAssertTrue(transcript.contains("> Hello"))

        let lossless = root.appendingPathComponent("lossless")
        try Exporter.writeDay(frames: frames, texts: [:], title: "Day", root: root, format: .bestQuality, into: lossless)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: lossless.path).sorted(), ["093005.png", "093105-d1.png", "transcript.md"])
    }
}

final class ActivityNavigationTests: XCTestCase {
    private let day = { (offset: Int) in Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: Date()))! }

    func testTheTimelineOpensOnTodayUnlessTodayIsEmpty() {
        let today = day(0)
        XCTAssertEqual(Activity.initialDay(today: today, daysWithFrames: [today, day(-1)]), today)
        XCTAssertEqual(Activity.initialDay(today: today, daysWithFrames: [day(-3), day(-1), day(-2)]), day(-1))
        XCTAssertEqual(Activity.initialDay(today: today, daysWithFrames: []), today)
        XCTAssertEqual(Activity.initialDay(today: today, daysWithFrames: [day(1)]), today)
    }

    func testJumpingBetweenAppSwitches() {
        let apps = ["Mail", "Mail", "Mail", "Safari", "Safari", "Notes", "Mail"]
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 0, direction: 1), 3)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 2, direction: 1), 3)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 3, direction: 1), 5)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 5, direction: 1), 6)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 6, direction: 1), 6)

        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 2, direction: -1), 0)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 0, direction: -1), 0)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 4, direction: -1), 3)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 3, direction: -1), 0)
        XCTAssertEqual(Activity.switchIndex(apps: apps, from: 6, direction: -1), 5)
        XCTAssertEqual(Activity.switchIndex(apps: [], from: 0, direction: 1), 0)
    }
}

final class OrphanCleanupTests: XCTestCase {
    func testNothingIsDeletedWhenMostFilesLookOrphaned() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ts-orphans-\(UUID().uuidString)")
        let frames = dir.appendingPathComponent("frames/day")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try Database(path: dir.appendingPathComponent("index.sqlite").path)
        for n in 1...5 {
            let url = frames.appendingPathComponent("f\(n).heic")
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3600)], ofItemAtPath: url.path)
        }
        try await db.insert(date: Date(), app: "A", title: "", path: "day/f1.heic", text: "x")
        let removed = await Storage.removeOrphans(root: dir.appendingPathComponent("frames"), db: db)
        XCTAssertEqual(removed, 0)
        let empty = try Database(path: dir.appendingPathComponent("empty.sqlite").path)
        let none = await Storage.removeOrphans(root: dir.appendingPathComponent("frames"), db: empty)
        XCTAssertEqual(none, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: frames.path).count, 5)
    }

    func testOnlyOldFilesWithoutAnIndexEntryAreRemoved() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ts-orphans-\(UUID().uuidString)")
        let frames = dir.appendingPathComponent("frames")
        try FileManager.default.createDirectory(at: frames.appendingPathComponent("2026-10-13"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try Database(path: dir.appendingPathComponent("index.sqlite").path)

        func write(_ name: String, ageSeconds: Double) throws {
            let url = frames.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ageSeconds)], ofItemAtPath: url.path)
        }
        for n in 1...6 {
            try write("2026-10-13/known\(n).heic", ageSeconds: 3600)
            try await db.insert(date: Date().addingTimeInterval(Double(n)), app: "A", title: "", path: "2026-10-13/known\(n).heic", text: "x")
        }
        try write("2026-10-13/orphan-old.heic", ageSeconds: 3600)
        try write("2026-10-13/orphan-new.heic", ageSeconds: 5)
        try write("2026-10-12/lonely-orphan.heic", ageSeconds: 7200)

        let removed = await Storage.removeOrphans(root: frames, db: db)
        XCTAssertEqual(removed, 2)
        let left = try FileManager.default.subpathsOfDirectory(atPath: frames.path).filter { $0.hasSuffix(".heic") }.sorted()
        XCTAssertEqual(left, (1...6).map { "2026-10-13/known\($0).heic" } + ["2026-10-13/orphan-new.heic"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: frames.appendingPathComponent("2026-10-12").path))
    }
}

final class TextHighlightTests: XCTestCase {
    func testFindsEveryOccurrenceIgnoringCaseAndAccents() {
        let text = "Budget notes: the budget is tight. Café budgets."
        let ranges = TextHighlight.ranges(in: text, terms: ["budget"])
        XCTAssertEqual(ranges.map { String(text[$0]) }, ["Budget", "budget", "budget"])
        XCTAssertEqual(TextHighlight.ranges(in: text, terms: ["cafe"]).map { String(text[$0]) }, ["Café"])
    }

    func testSeveralTermsAreSortedAndEmptyTermsIgnored() {
        let text = "alpha beta alpha"
        let ranges = TextHighlight.ranges(in: text, terms: ["beta", "", "alpha"])
        XCTAssertEqual(ranges.map { String(text[$0]) }, ["alpha", "beta", "alpha"])
        XCTAssertTrue(TextHighlight.ranges(in: text, terms: []).isEmpty)
        XCTAssertTrue(TextHighlight.ranges(in: text, terms: ["zzz"]).isEmpty)
    }
}

final class DatabaseRecoveryTests: XCTestCase {
    private func scratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ts-recovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir
    }

    func testAHealthyIndexOpensWithoutANotice() async throws {
        let support = try scratch()
        let first = DatabaseRecovery.open(support: support)
        _ = try await first.database.insert(date: Date(), app: "A", title: "", path: "a.jpg", text: "hello")
        XCTAssertNil(first.notice)
        let again = DatabaseRecovery.open(support: support)
        XCTAssertNil(again.notice)
        let frames = try await again.database.frames(on: Date())
        XCTAssertEqual(frames.map(\.path), ["a.jpg"])
    }

    func testADamagedIndexIsMovedAsideAndReplaced() async throws {
        let support = try scratch()
        try Data("this is not a database at all, just text".utf8).write(to: support.appendingPathComponent("index.sqlite"))
        let store = DatabaseRecovery.open(support: support)
        XCTAssertNotNil(store.notice)
        let names = try FileManager.default.contentsOfDirectory(atPath: support.path)
        XCTAssertTrue(names.contains { $0.hasPrefix("index.damaged-") })
        _ = try await store.database.insert(date: Date(), app: "A", title: "", path: "b.jpg", text: "fresh")
        let hits = try await store.database.search("fresh")
        XCTAssertEqual(hits.count, 1)
    }

    func testAnUnwritableFolderFallsBackToATemporaryOne() async throws {
        let blocker = try scratch().appendingPathComponent("file")
        try Data("x".utf8).write(to: blocker)
        let store = DatabaseRecovery.open(support: blocker.appendingPathComponent("TimeScreen"))
        XCTAssertNotNil(store.notice)
        _ = try await store.database.insert(date: Date(), app: "A", title: "", path: "c.jpg", text: "still works")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.framesRoot.path))
    }
}

final class CaptureCadenceTests: XCTestCase {
    func testCapturesGetSparserTheLongerTheMacIsUntouched() {
        XCTAssertEqual(CaptureCadence.interval(base: 5, idleSeconds: 0), 5)
        XCTAssertEqual(CaptureCadence.interval(base: 5, idleSeconds: 59), 5)
        XCTAssertEqual(CaptureCadence.interval(base: 5, idleSeconds: 60), 15)
        XCTAssertEqual(CaptureCadence.interval(base: 5, idleSeconds: 299), 15)
        XCTAssertEqual(CaptureCadence.interval(base: 5, idleSeconds: 300), 30)
    }

    func testASlowBaseIntervalIsNeverSpedUp() {
        XCTAssertEqual(CaptureCadence.interval(base: 60, idleSeconds: 120), 60)
        XCTAssertEqual(CaptureCadence.interval(base: 60, idleSeconds: 900), 60)
        XCTAssertEqual(CaptureCadence.interval(base: 20, idleSeconds: 120), 20)
    }

    func testTheIdleReadingIsSane() {
        XCTAssertGreaterThanOrEqual(CaptureCadence.idleSeconds, 0)
    }
}

final class SearchQueryTests: XCTestCase {
    func testPlainWordsMatchAsPrefixes() {
        XCTAssertEqual(SearchQuery("concurr swift").matchExpression, "\"concurr\"* \"swift\"*")
        XCTAssertNil(SearchQuery("   ").matchExpression)
        XCTAssertNil(SearchQuery("").matchExpression)
    }

    func testQuotedPhrasesMatchExactly() {
        XCTAssertEqual(SearchQuery("\"offsite budget\"").matchExpression, "\"offsite budget\"")
        XCTAssertEqual(SearchQuery("notes \"offsite   budget\" travel").matchExpression, "\"notes\"* \"offsite budget\" \"travel\"*")
        XCTAssertEqual(SearchQuery("\"unfinished phrase").matchExpression, "\"unfinished phrase\"")
        XCTAssertNil(SearchQuery("\"\"").matchExpression)
    }

    func testAMinusLeavesAWordOrPhraseOut() {
        XCTAssertEqual(SearchQuery("budget -travel").matchExpression, "(\"budget\"*) NOT (\"travel\"*)")
        XCTAssertEqual(SearchQuery("budget -travel -\"hotel costs\"").matchExpression,
                       "(\"budget\"*) NOT (\"travel\"* OR \"hotel costs\")")
        XCTAssertNil(SearchQuery("-travel").matchExpression)
        XCTAssertEqual(SearchQuery("e-mail").matchExpression, "\"e-mail\"*")
        XCTAssertEqual(SearchQuery("budget -").matchExpression, "\"budget\"* \"-\"*")
    }

    func testStrayQuotesInsideAWordAreDropped() {
        XCTAssertEqual(SearchQuery("hello wor\"ld").matchExpression, "\"hello\"* \"world\"*")
    }

    func testHighlightTermsSkipExcludedWordsAndSplitPhrases() {
        XCTAssertEqual(SearchQuery("Budget \"Offsite Plan\" -travel").highlightTerms, ["budget", "offsite", "plan"])
        XCTAssertTrue(SearchQuery("-travel").highlightTerms.isEmpty)
    }
}

final class PhraseSearchTests: XCTestCase {
    func testSearchHonoursPhrasesAndExclusions() async throws {
        let path = NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite"
        let db = try Database(path: path)
        let now = Date()
        try await db.insert(date: now, app: "Notes", title: "", path: "a.jpg", text: "the offsite budget is tight and travel is costly")
        try await db.insert(date: now.addingTimeInterval(1), app: "Notes", title: "", path: "b.jpg", text: "budget for the offsite, travel booked")
        try await db.insert(date: now.addingTimeInterval(2), app: "Notes", title: "", path: "c.jpg", text: "offsite plan without numbers")

        let phrase = try await db.search("\"offsite budget\"")
        XCTAssertEqual(phrase.map(\.frame.path), ["a.jpg"])
        let both = try await db.search("offsite budget")
        XCTAssertEqual(Set(both.map(\.frame.path)), ["a.jpg", "b.jpg"])
        let without = try await db.search("budget -costly")
        XCTAssertEqual(without.map(\.frame.path), ["b.jpg"])
        let withoutPhrase = try await db.search("offsite -\"offsite budget\"")
        XCTAssertEqual(Set(withoutPhrase.map(\.frame.path)), ["b.jpg", "c.jpg"])
        let onlyNegative = try await db.search("-budget")
        XCTAssertTrue(onlyNegative.isEmpty)

        for odd in ["budget -", "- -", "(budget)", "budget AND travel", "budget OR", "\"", "*", "a\"b\"c", "NOT", "near/3 budget", "col:budget"] {
            do { _ = try await db.search(odd) } catch { XCTFail("search for \(odd) threw \(error)") }
        }
    }
}

final class PreviewZoomTests: XCTestCase {
    private let size = CGSize(width: 800, height: 500)

    func testScaleStaysWithinTheLimits() {
        var zoom = PreviewZoom()
        zoom.set(scale: 0.2, in: size)
        XCTAssertEqual(zoom.scale, 1)
        XCTAssertFalse(zoom.isZoomed)
        zoom.set(scale: 50, in: size)
        XCTAssertEqual(zoom.scale, 6)
        zoom.zoom(by: 2, in: size)
        XCTAssertEqual(zoom.scale, 6)
        zoom.zoom(by: 0.5, in: size)
        XCTAssertEqual(zoom.scale, 3)
        XCTAssertTrue(zoom.isZoomed)
    }

    func testPanningCannotUncoverTheEdges() {
        var zoom = PreviewZoom()
        zoom.pan(to: CGSize(width: 300, height: 300), in: size)
        XCTAssertEqual(zoom.offset, .zero)
        zoom.set(scale: 2, in: size)
        zoom.pan(to: CGSize(width: 1000, height: -1000), in: size)
        XCTAssertEqual(zoom.offset, CGSize(width: 400, height: -250))
        zoom.pan(to: CGSize(width: 10, height: 20), in: size)
        XCTAssertEqual(zoom.offset, CGSize(width: 10, height: 20))
    }

    func testZoomingBackOutPullsTheImageBackIntoView() {
        var zoom = PreviewZoom()
        zoom.set(scale: 4, in: size)
        zoom.pan(to: CGSize(width: 1200, height: 700), in: size)
        XCTAssertEqual(zoom.offset, CGSize(width: 1200, height: 700))
        zoom.set(scale: 2, in: size)
        XCTAssertEqual(zoom.offset, CGSize(width: 400, height: 250))
        zoom.reset()
        XCTAssertEqual(zoom.offset, .zero)
        XCTAssertEqual(zoom.scale, 1)
    }
}

final class StarredFramesTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        try Database(path: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite")
    }

    func testStarringIsStoredAndListedNewestFirst() async throws {
        let db = try makeDatabase()
        let now = Date()
        let a = try await db.insert(date: now.addingTimeInterval(-30), app: "A", title: "one", path: "a.jpg", text: "alpha")
        _ = try await db.insert(date: now.addingTimeInterval(-20), app: "B", title: "two", path: "b.jpg", text: "beta")
        let c = try await db.insert(date: now.addingTimeInterval(-10), app: "C", title: "three", path: "c.jpg", text: "gamma")
        try await db.setStarred(true, id: a)
        try await db.setStarred(true, id: c)
        let starred = try await db.starredFrames()
        XCTAssertEqual(starred.map(\.path), ["c.jpg", "a.jpg"])
        XCTAssertTrue(starred.allSatisfy(\.starred))
        let all = try await db.frames(on: now)
        XCTAssertEqual(all.map(\.starred), [true, false, true])
        try await db.setStarred(false, id: a)
        let remaining = try await db.starredFrames()
        XCTAssertEqual(remaining.map(\.path), ["c.jpg"])
        let latest = try await db.latestFrame()
        XCTAssertEqual(latest?.path, "c.jpg")
        let hit = try await db.search("gamma")
        XCTAssertEqual(hit.first?.frame.starred, true)
    }

    func testStarredFramesSurviveRetentionTheSizeLimitAndCompaction() async throws {
        let db = try makeDatabase()
        let old = Date().addingTimeInterval(-10 * 86_400)
        let keep = try await db.insert(date: old, app: "A", title: "", path: "keep.jpg", text: "keep me")
        _ = try await db.insert(date: old.addingTimeInterval(1), app: "A", title: "", path: "drop.jpg", text: "drop me")
        try await db.setStarred(true, id: keep)

        let oldest = try await db.oldestFrames(limit: 10)
        XCTAssertEqual(oldest.map(\.path), ["drop.jpg"])
        let compactable = try await db.framesToCompact(before: Date(), limit: 10)
        XCTAssertEqual(compactable.map(\.path), ["drop.jpg"])

        let removed = try await db.prune(before: Date().addingTimeInterval(-86_400))
        XCTAssertEqual(removed, ["drop.jpg"])
        let left = try await db.frames(on: old)
        XCTAssertEqual(left.map(\.path), ["keep.jpg"])
        let hits = try await db.search("keep")
        XCTAssertEqual(hits.count, 1)
        let boxesGone = try await db.search("drop")
        XCTAssertTrue(boxesGone.isEmpty)
    }

    func testTheSizeLimitNeverDeletesStarredFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ts-star-\(UUID().uuidString)")
        let frames = dir.appendingPathComponent("frames/day")
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let db = try Database(path: dir.appendingPathComponent("index.sqlite").path)
        for n in 1...6 {
            try Data(repeating: 1, count: 64 * 1024).write(to: frames.appendingPathComponent("f\(n).heic"))
            let id = try await db.insert(date: Date().addingTimeInterval(Double(n)), app: "A", title: "", path: "day/f\(n).heic", text: "x")
            if n <= 2 { try await db.setStarred(true, id: id) }
        }
        let removed = await Storage.enforce(cap: 1, root: dir.appendingPathComponent("frames"), db: db)
        XCTAssertTrue(removed)
        let files = try FileManager.default.contentsOfDirectory(atPath: frames.path).sorted()
        XCTAssertEqual(files, ["f1.heic", "f2.heic"])
    }
}

final class SummaryWindowTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: hour, minute: minute, second: second))!
    }

    func testBlocksAreQuarterHours() {
        let block = SummaryWindow.block(containing: date(14, 37, 12), calendar: calendar)
        XCTAssertEqual(block.start, date(14, 30))
        XCTAssertEqual(block.end, date(14, 45))
        XCTAssertEqual(block.key, "2026-10-13 14:30")
        XCTAssertEqual(SummaryWindow.block(containing: date(14, 30), calendar: calendar).start, date(14, 30))
        XCTAssertEqual(SummaryWindow.block(containing: date(14, 59, 59), calendar: calendar).start, date(14, 45))
        XCTAssertEqual(SummaryWindow.block(containing: date(0, 0), calendar: calendar).key, "2026-10-13 00:00")
    }

    func testHoursAndDaysAndTheirParts() {
        let hour = SummaryWindow.hour(containing: date(9, 20), calendar: calendar)
        XCTAssertEqual(hour.key, "2026-10-13 09")
        XCTAssertEqual(hour.blocks(calendar: calendar).map(\.key), ["2026-10-13 09:00", "2026-10-13 09:15", "2026-10-13 09:30", "2026-10-13 09:45"])
        let day = SummaryWindow.day(containing: date(9, 20), calendar: calendar)
        XCTAssertEqual(day.key, "2026-10-13")
        XCTAssertEqual(day.hours(calendar: calendar).count, 24)
        XCTAssertEqual(day.hours(calendar: calendar).first?.key, "2026-10-13 00")
        XCTAssertEqual(day.blocks(calendar: calendar).count, 96)
        XCTAssertTrue(SummaryWindow.block(containing: date(9, 0), calendar: calendar).blocks(calendar: calendar).isEmpty)
    }

    func testAppAndFrameKeys() {
        XCTAssertEqual(SummaryWindow.app("Mail", on: date(10, 0), calendar: calendar).key, "2026-10-13|Mail")
        let frame = Frame(id: 42, date: date(10, 0), app: "Mail", title: "", path: "x")
        XCTAssertEqual(SummaryWindow.frame(frame).key, "42")
        XCTAssertEqual(SummaryWindow.frame(frame).kind, .frame)
    }
}

final class SummaryInputTests: XCTestCase {
    func testSamplingKeepsTheEndsAndSpreadsTheRest() {
        XCTAssertEqual(SummaryInput.sample(Array(0..<10), limit: 4), [0, 3, 6, 9])
        XCTAssertEqual(SummaryInput.sample(Array(0..<3), limit: 10), [0, 1, 2])
        XCTAssertEqual(SummaryInput.sample(Array(0..<100), limit: 2), [0, 99])
        XCTAssertEqual(SummaryInput.sample(Array(0..<5), limit: 1), [0])
        XCTAssertTrue(SummaryInput.sample([Int](), limit: 5).isEmpty)
    }

    func testRepeatedChromeIsDroppedAndNewLinesKeptInOrder() {
        let frames = (1...10).map { "Menu Bar File Edit\nSidebar\nline \($0)\nshared note" }
        let condensed = SummaryInput.condense(frames, maxCharacters: 10_000)
        XCTAssertFalse(condensed.contains("Menu Bar"))
        XCTAssertFalse(condensed.contains("Sidebar"))
        XCTAssertFalse(condensed.contains("shared note"))
        XCTAssertEqual(condensed.split(separator: "\n").map(String.init), (1...10).map { "line \($0)" })
    }

    func testFewFramesKeepEverythingOnceAndTheBudgetIsHonoured() {
        let condensed = SummaryInput.condense(["alpha beta\nalpha beta\ngamma delta", "alpha beta\nepsilon"], maxCharacters: 10_000)
        XCTAssertEqual(condensed.split(separator: "\n").map(String.init), ["alpha beta", "gamma delta", "epsilon"])
        let limited = SummaryInput.condense(["aaaa aaaa\nbbbb bbbb\ncccc cccc"], maxCharacters: 22)
        XCTAssertEqual(limited, "aaaa aaaa\nbbbb bbbb")
        XCTAssertEqual(SummaryInput.condense(["a\n  \nbb"], maxCharacters: 100), "")
        XCTAssertEqual(SummaryInput.shorten("abcdef", to: 3), "abc")
        XCTAssertEqual(SummaryInput.shorten("ab", to: 3), "ab")
    }

    func testPromptsCarryTheFactsTheModelNeeds() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let stretch = SummaryPrompt.stretch(label: "09:00–09:15", apps: [("Mail", 3), ("Notes", 9)], text: "hello")
        XCTAssertTrue(stretch.contains("Notes (9 screenshots), Mail (3 screenshots)"))
        XCTAssertTrue(stretch.contains("09:00–09:15"))
        let frame = SummaryPrompt.frame(app: "Mail", title: "Inbox", date: start, text: "hi")
        XCTAssertTrue(frame.contains("App: Mail") && frame.contains("Window: Inbox") && frame.contains("hi"))
        XCTAssertFalse(SummaryPrompt.frame(app: "Mail", title: "", date: start, text: "hi").contains("Window:"))
        let rollup = SummaryPrompt.rollup(title: "Hour 9", notes: [("09:00–09:15", "Read mail."), ("09:15–09:30", "Wrote notes.")], maxSentences: 3)
        XCTAssertTrue(rollup.contains("09:00–09:15: Read mail.\n09:15–09:30: Wrote notes."))
        XCTAssertTrue(rollup.contains("at most 3 sentences"))
        XCTAssertEqual(SummaryPrompt.timeLabel(start, start.addingTimeInterval(900)).count, 11)
    }
}

final class SummaryStoreTests: XCTestCase {
    private func makeDatabase() throws -> Database {
        try Database(path: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite")
    }

    private func record(_ kind: SummaryKind, _ key: String, start: Date, end: Date, text: String = "text", inputs: Int = 1) -> SummaryRecord {
        SummaryRecord(kind: kind, key: key, start: start, end: end, text: text, inputs: inputs, created: Date())
    }

    func testSummariesAreSavedReplacedAndListed() async throws {
        let db = try makeDatabase()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try await db.saveSummary(record(.block, "b1", start: start, end: start.addingTimeInterval(900), text: "first"))
        try await db.saveSummary(record(.block, "b2", start: start.addingTimeInterval(900), end: start.addingTimeInterval(1800)))
        try await db.saveSummary(record(.block, "b1", start: start, end: start.addingTimeInterval(900), text: "replaced", inputs: 7))
        let one = try await db.summary(kind: .block, key: "b1")
        XCTAssertEqual(one?.text, "replaced")
        XCTAssertEqual(one?.inputs, 7)
        let missing = try await db.summary(kind: .hour, key: "b1")
        XCTAssertNil(missing)
        let listed = try await db.summaries(kind: .block, from: start, to: start.addingTimeInterval(3600))
        XCTAssertEqual(listed.map(\.key), ["b1", "b2"])
        let count = try await db.summaryCount()
        XCTAssertEqual(count, 2)
        try await db.deleteAllSummaries()
        let none = try await db.summaryCount()
        XCTAssertEqual(none, 0)
    }

    func testDeletingFramesRemovesTheSummariesThatCoverThem() async throws {
        let db = try makeDatabase()
        let base = Date().addingTimeInterval(-86_400 * 3)
        let a = try await db.insert(date: base, app: "A", title: "", path: "a", text: "one")
        let b = try await db.insert(date: base.addingTimeInterval(7200), app: "A", title: "", path: "b", text: "two")
        try await db.saveSummary(record(.block, "covers-a", start: base.addingTimeInterval(-60), end: base.addingTimeInterval(840)))
        try await db.saveSummary(record(.block, "covers-b", start: base.addingTimeInterval(7200), end: base.addingTimeInterval(8100)))
        try await db.saveSummary(record(.day, "all-day", start: base.addingTimeInterval(-3600), end: base.addingTimeInterval(86_400)))
        try await db.saveSummary(record(.block, "elsewhere", start: base.addingTimeInterval(40_000), end: base.addingTimeInterval(40_900)))

        try await db.delete(ids: [a])
        let afterFirst = try await db.summaries(kind: .block, from: base.addingTimeInterval(-86_400), to: base.addingTimeInterval(86_400 * 2))
        XCTAssertEqual(afterFirst.map(\.key), ["covers-b", "elsewhere"])
        let day = try await db.summary(kind: .day, key: "all-day")
        XCTAssertNil(day)

        try await db.delete(ids: [b])
        let afterSecond = try await db.summaries(kind: .block, from: base.addingTimeInterval(-86_400), to: base.addingTimeInterval(86_400 * 2))
        XCTAssertEqual(afterSecond.map(\.key), ["elsewhere"])
        try await db.delete(ids: [])
    }

    func testPruningAndDeleteAllClearSummaries() async throws {
        let db = try makeDatabase()
        let old = Date().addingTimeInterval(-86_400 * 40)
        _ = try await db.insert(date: old, app: "A", title: "", path: "o", text: "old")
        try await db.saveSummary(record(.hour, "old-hour", start: old, end: old.addingTimeInterval(3600)))
        try await db.saveSummary(record(.hour, "new-hour", start: Date(), end: Date().addingTimeInterval(3600)))
        _ = try await db.prune(before: Date().addingTimeInterval(-86_400 * 30))
        let remaining = try await db.summaryCount()
        XCTAssertEqual(remaining, 1)
        try await db.deleteAll()
        let none = try await db.summaryCount()
        XCTAssertEqual(none, 0)
    }
}

final class StubGenerator: TextGenerator, @unchecked Sendable {
    var contextSize: Int
    private(set) var prompts: [String] = []
    private(set) var instructions: [String] = []
    var failFirstWith: Error?
    private var calls = 0

    init(contextSize: Int = 8192) { self.contextSize = contextSize }

    var callCount: Int { calls }

    func tokenCount(_ text: String) async -> Int { text.count / 3 }

    func generate(instructions: String, prompt: String, maxTokens: Int) async throws -> String {
        calls += 1
        prompts.append(prompt)
        self.instructions.append(instructions)
        if calls == 1, let failFirstWith { throw failFirstWith }
        return "Summary \(calls)."
    }
}

private struct FakeContextError: Error, CustomStringConvertible {
    var description: String { "contextSizeExceeded(contextSize: 10, tokenCount: 99)" }
}

final class SummaryServiceTests: XCTestCase {
    private let calendar = Calendar.current
    private lazy var day: Date = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: Date()))!

    private func at(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: second, of: day)!
    }

    private func make(_ generator: StubGenerator = StubGenerator()) throws -> (Database, SummaryService, StubGenerator) {
        let db = try Database(path: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite")
        return (db, SummaryService(db: db, generator: generator), generator)
    }

    @discardableResult
    private func addFrame(_ db: Database, _ date: Date, app: String = "Mail", text: String) async throws -> Int64 {
        try await db.insert(date: date, app: app, title: "T", path: "\(UUID().uuidString).jpg", text: text)
    }

    func testAFrameSummaryIsCachedUntilRegenerated() async throws {
        let (db, service, generator) = try make()
        let id = try await addFrame(db, at(9, 2), text: "Quarterly budget review\nTravel costs")
        let frame = try await db.frame(id: id)!
        let first = try await service.summarize(.frame(frame))
        XCTAssertEqual(first?.text, "Summary 1.")
        XCTAssertTrue(generator.prompts[0].contains("Quarterly budget review"))
        XCTAssertTrue(generator.prompts[0].contains("App: Mail"))
        let second = try await service.summarize(.frame(frame))
        XCTAssertEqual(second?.text, "Summary 1.")
        XCTAssertEqual(generator.callCount, 1)
        let again = try await service.summarize(.frame(frame), regenerate: true)
        XCTAssertEqual(again?.text, "Summary 2.")
        XCTAssertEqual(generator.callCount, 2)
    }

    func testAFrameWithNoTextThrows() async throws {
        let (db, service, generator) = try make()
        let id = try await addFrame(db, at(9, 2), text: "   ")
        let frame = try await db.frame(id: id)!
        do {
            _ = try await service.summarize(.frame(frame))
            XCTFail("expected an error")
        } catch let error as SummaryError {
            XCTAssertEqual(error, .noText)
        }
        XCTAssertEqual(generator.callCount, 0)
    }

    func testABlockSummaryDropsRepeatedChromeAndGoesStaleWhenFramesAreAdded() async throws {
        let (db, service, generator) = try make()
        for n in 0..<6 {
            try await addFrame(db, at(9, 1, n * 10), text: "Menu Bar File Edit\nunique line \(n)")
        }
        let window = SummaryWindow.block(containing: at(9, 5))
        let first = try await service.summarize(window)
        XCTAssertEqual(first?.inputs, 6)
        XCTAssertTrue(generator.prompts[0].contains("unique line 0"))
        XCTAssertTrue(generator.prompts[0].contains("unique line 5"))
        XCTAssertFalse(generator.prompts[0].contains("Menu Bar"))
        XCTAssertTrue(generator.prompts[0].contains("Mail (6 screenshots)"))
        let pendingBefore = try await service.pendingCount(window)
        XCTAssertEqual(pendingBefore, 0)
        _ = try await service.summarize(window)
        XCTAssertEqual(generator.callCount, 1)

        try await addFrame(db, at(9, 12), text: "a new line")
        let pendingAfter = try await service.pendingCount(window)
        XCTAssertEqual(pendingAfter, 1)
        let refreshed = try await service.summarize(window)
        XCTAssertEqual(refreshed?.inputs, 7)
        XCTAssertEqual(generator.callCount, 2)
    }

    func testAnEmptyBlockHasNoSummary() async throws {
        let (_, service, generator) = try make()
        let result = try await service.summarize(.block(containing: at(9, 5)))
        XCTAssertNil(result)
        XCTAssertEqual(generator.callCount, 0)
    }

    func testAnHourIsBuiltFromItsBlocksWithProgress() async throws {
        let (db, service, generator) = try make()
        try await addFrame(db, at(9, 2), text: "first block text")
        try await addFrame(db, at(9, 20), text: "second block text")
        let hour = SummaryWindow.hour(containing: at(9, 0))
        let pending = try await service.pendingCount(hour)
        XCTAssertEqual(pending, 3)

        final class Log: @unchecked Sendable { var steps: [[Int]] = [] }
        let log = Log()
        let record = try await service.summarize(hour) { done, total in log.steps.append([done, total]) }
        XCTAssertEqual(generator.callCount, 3)
        XCTAssertEqual(record?.inputs, 2)
        XCTAssertEqual(log.steps, [[1, 3], [2, 3], [3, 3]])
        XCTAssertTrue(generator.prompts[2].contains("Summary 1."))
        XCTAssertTrue(generator.prompts[2].contains("Summary 2."))
        XCTAssertEqual(generator.instructions[2], SummaryPrompt.rollupInstructions)

        _ = try await service.summarize(hour)
        XCTAssertEqual(generator.callCount, 3)
        let none = try await service.pendingCount(hour)
        XCTAssertEqual(none, 0)

        try await addFrame(db, at(9, 40), text: "third block text")
        let afterAdding = try await service.pendingCount(hour)
        XCTAssertEqual(afterAdding, 2)
    }

    func testADayIsBuiltFromBlocksThenHoursThenTheDay() async throws {
        let (db, service, generator) = try make()
        try await addFrame(db, at(9, 2), text: "morning text")
        try await addFrame(db, at(14, 40), text: "afternoon text")
        let record = try await service.summarize(.day(containing: at(12, 0)))
        XCTAssertEqual(generator.callCount, 5)
        XCTAssertEqual(record?.inputs, 2)
        XCTAssertEqual(record?.kind, .day)
        let hours = try await db.summaries(kind: .hour, from: at(0, 0), to: at(23, 59))
        XCTAssertEqual(hours.count, 2)
    }

    func testAnAppSummaryUsesOnlyThatAppsText() async throws {
        let (db, service, generator) = try make()
        try await addFrame(db, at(9, 2), app: "Mail", text: "inbox subject lines")
        try await addFrame(db, at(9, 3), app: "Notes", text: "grocery list")
        let record = try await service.summarize(.app("Mail", on: at(12, 0)))
        XCTAssertEqual(record?.inputs, 1)
        XCTAssertTrue(generator.prompts[0].contains("inbox subject lines"))
        XCTAssertFalse(generator.prompts[0].contains("grocery"))
        let nothing = try await service.summarize(.app("Music", on: at(12, 0)))
        XCTAssertNil(nothing)
    }

    func testALongPromptIsTrimmedToFitASmallWindow() async throws {
        let (db, service, generator) = try make(StubGenerator(contextSize: 1200))
        let long = (0..<3000).map { "distinct line number \($0)" }.joined(separator: "\n")
        let id = try await addFrame(db, at(9, 2), text: long)
        let frame = try await db.frame(id: id)!
        _ = try await service.summarize(.frame(frame))
        let tokens = (generator.instructions[0] + "\n" + generator.prompts[0]).count / 3
        XCTAssertLessThanOrEqual(tokens, 1200 - SummaryService.outputTokens - 300)
        XCTAssertGreaterThan(generator.prompts[0].count, 100)
    }

    func testRecapsNeverReadMoreThanTheInputCapEvenInABigWindow() async throws {
        let (db, service, generator) = try make(StubGenerator(contextSize: 8192))
        for n in 0..<30 {
            try await addFrame(db, at(9, 1, n), text: (0..<400).map { "frame \(n) distinct line \($0) with some words" }.joined(separator: "\n"))
        }
        _ = try await service.summarize(.block(containing: at(9, 5)))
        let tokens = (generator.instructions[0] + "\n" + generator.prompts[0]).count / 3
        XCTAssertLessThanOrEqual(tokens, SummaryService.inputTokens)
        XCTAssertGreaterThan(tokens, SummaryService.inputTokens / 2)
        XCTAssertEqual(SummaryService.outputTokens, 110)
    }

    func testAContextOverflowFromTheModelIsRetriedWithLessText() async throws {
        let generator = StubGenerator()
        generator.failFirstWith = FakeContextError()
        let (db, service, _) = try make(generator)
        let id = try await addFrame(db, at(9, 2), text: String(repeating: "x ", count: 6000))
        let frame = try await db.frame(id: id)!
        let record = try await service.summarize(.frame(frame))
        XCTAssertNotNil(record)
        XCTAssertEqual(generator.callCount, 2)
        XCTAssertLessThan(generator.prompts[1].count, generator.prompts[0].count)
    }

    func testOtherModelErrorsSurfaceAsFailures() async throws {
        struct Boom: Error, LocalizedError { var errorDescription: String? { "the model is busy" } }
        let generator = StubGenerator()
        generator.failFirstWith = Boom()
        let (db, service, _) = try make(generator)
        let id = try await addFrame(db, at(9, 2), text: "something to read")
        let frame = try await db.frame(id: id)!
        do {
            _ = try await service.summarize(.frame(frame))
            XCTFail("expected an error")
        } catch let error as SummaryError {
            XCTAssertEqual(error, .failed("the model is busy"))
        }
        let cached = await service.cached(.frame(frame))
        XCTAssertNil(cached)
    }

    func testOutputIsCleanedUp() throws {
        XCTAssertEqual(try SummaryService.clean("  Summary: Read mail.\nThen wrote notes.  "), "Read mail. Then wrote notes.")
        XCTAssertThrowsError(try SummaryService.clean("  \n "))
        XCTAssertEqual(try SummaryService.clean("You read mail about the budget. Then you opened Safari and star"), "You read mail about the budget.")
        XCTAssertEqual(try SummaryService.clean("You read mail about the budget."), "You read mail about the budget.")
        XCTAssertEqual(try SummaryService.clean("Short cut off wi"), "Short cut off wi")
        XCTAssertEqual(try SummaryService.clean("You read mail (and notes)"), "You read mail (and notes)")
        XCTAssertTrue(SummaryService.isContextOverflow(FakeContextError()))
        XCTAssertFalse(SummaryService.isContextOverflow(CocoaError(.fileNoSuchFile)))
    }
}

/// Talks to Apple's real on-device model. Skipped on Macs where it is not available.
final class LiveSummaryTests: XCTestCase {
    func testTheOnDeviceModelSummarizesFictionalScreens() async throws {
        let availability = SystemModel.availability
        try XCTSkipUnless(availability == .available, availability.message ?? "model unavailable")
        let generator = try XCTUnwrap(SystemModel.makeGenerator())
        XCTAssertGreaterThan(generator.contextSize, 1000)

        let db = try Database(path: NSTemporaryDirectory() + "timescreen-\(UUID().uuidString).sqlite")
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -3, to: calendar.startOfDay(for: Date()))!
        func at(_ hour: Int, _ minute: Int) -> Date { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)! }
        let mail = "Inbox\nRe: offsite budget\nMaya Chen: the revised budget looks good, travel is the biggest line item\nInvoice 2041 is ready"
        let code = "$ swift test\nTest Case 'DatabaseTests.testInsert' passed\nTest Case 'DatabaseTests.testSearch' passed\nExecuted 12 tests, with 0 failures"
        for n in 0..<4 { _ = try await db.insert(date: at(9, 2 + n), app: "Mail", title: "Inbox", path: "m\(n)", text: mail + "\nline \(n)") }
        for n in 0..<4 { _ = try await db.insert(date: at(9, 20 + n), app: "Terminal", title: "swift test", path: "t\(n)", text: code + "\nrun \(n)") }

        let service = SummaryService(db: db, generator: generator)
        let block = try await service.summarize(.block(containing: at(9, 5)))
        let blockText = try XCTUnwrap(block?.text)
        print("BLOCK SUMMARY:", blockText)
        XCTAssertFalse(blockText.isEmpty)
        XCTAssertLessThan(blockText.count, 700)

        let hour = try await service.summarize(.hour(containing: at(9, 0)))
        print("HOUR SUMMARY:", hour?.text ?? "nil")
        XCTAssertEqual(hour?.inputs, 2)
        let again = try await service.pendingCount(.hour(containing: at(9, 0)))
        XCTAssertEqual(again, 0)
    }
}
