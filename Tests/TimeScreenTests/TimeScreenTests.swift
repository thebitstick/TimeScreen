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
