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
