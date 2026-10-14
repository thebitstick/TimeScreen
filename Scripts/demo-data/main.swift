import AppKit
import Foundation

// Draws a fictional day of screenshots, runs the app's real OCR on them and fills a data folder.
// Used for README screenshots: no real screen content is involved. See Scripts/make-demo-data.sh.

let width = 1728, height = 1080

struct Scene {
    let app: String
    let title: String
    let heading: String
    let lines: [String]
    let monospaced: Bool
}

let scenes: [String: [Scene]] = [
    "Mail": [
        Scene(app: "Mail", title: "Inbox", heading: "Inbox", lines: [
            "Maya Chen        Re: offsite budget          Thanks, the revised budget looks good to me.",
            "Billing          Invoice 2041 is ready       Your invoice for September is attached.",
            "Omar Haddad      Design review moved         Moving the review to Thursday at 10:00.",
            "Library          Hold available              Your hold on The Pragmatic Programmer is ready.",
            "Priya Nair       Trail map for Saturday      Here is the route we talked about, 14 km loop.",
        ], monospaced: false),
        Scene(app: "Mail", title: "Re: offsite budget", heading: "Re: offsite budget", lines: [
            "Hi Sam,", "I went through the numbers. Travel is the biggest line item, so I suggest we book the train",
            "early. Lodging fits inside the budget if we keep it to two nights.", "Can you confirm the headcount by Friday?",
            "Thanks,", "Maya",
        ], monospaced: false),
    ],
    "Safari": [
        Scene(app: "Safari", title: "Best hikes near Portland", heading: "Best hikes near Portland", lines: [
            "Wildwood Trail  |  30 miles  |  Moderate", "The longest urban trail in the country winds through Forest Park.",
            "Multnomah Falls  |  2.4 miles  |  Easy", "A short climb to the bridge with views of the 620 foot falls.",
            "Dog Mountain  |  6.9 miles  |  Hard", "Wildflowers peak in May, so start early to find parking.",
        ], monospaced: false),
        Scene(app: "Safari", title: "Swift concurrency overview", heading: "Concurrency in Swift", lines: [
            "Swift provides built-in support for writing asynchronous and parallel code.",
            "Use async functions to suspend without blocking a thread.", "Actors protect mutable state from data races.",
            "Task groups run child tasks concurrently and gather the results.", "Sendable types are safe to share across concurrency domains.",
        ], monospaced: false),
        Scene(app: "Safari", title: "Sourdough starter guide", heading: "Sourdough starter guide", lines: [
            "Day 1: mix 50 g of flour with 50 g of water and cover loosely.", "Day 3: discard half and feed with equal parts flour and water.",
            "Day 7: the starter should double in size within eight hours.", "Keep it warm, around 24 degrees, for the best rise.",
        ], monospaced: false),
    ],
    "Notes": [
        Scene(app: "Notes", title: "Weekend project plan", heading: "Weekend project plan", lines: [
            "- Build the bookshelf: cut the shelves, sand the edges, two coats of oil", "- Buy screws and wood glue (about 20 dollars)",
            "- Offsite budget: travel 600, lodging 450, meals 300", "- Call the landlord about the heating",
            "- Groceries: eggs, rice, tomatoes, basil, coffee",
        ], monospaced: false),
        Scene(app: "Notes", title: "Reading list", heading: "Reading list", lines: [
            "The Pragmatic Programmer", "Designing Data-Intensive Applications", "A Philosophy of Software Design",
            "Working in Public", "The Mythical Man-Month",
        ], monospaced: false),
    ],
    "Terminal": [
        Scene(app: "Terminal", title: "swift test", heading: "~/Developer/demo  swift test", lines: [
            "$ swift test", "Building for debugging...", "Test Suite 'All tests' started", "Test Case 'DatabaseTests.testInsert' passed (0.004 seconds)",
            "Test Case 'DatabaseTests.testSearch' passed (0.006 seconds)", "Test Case 'SignatureTests.testDuplicate' passed (0.001 seconds)",
            "Executed 3 tests, with 0 failures in 0.011 seconds",
        ], monospaced: true),
        Scene(app: "Terminal", title: "git log", heading: "~/Developer/demo  git log --oneline", lines: [
            "$ git log --oneline -6", "a1f3c9e Add the jump to time box", "7b20d4a Filter search results by app and date",
            "55e91c2 Stop capturing while the timeline is open", "c0d8e17 Skip private browsing windows", "19ab3f0 Initial commit",
        ], monospaced: true),
    ],
    "Calendar": [
        Scene(app: "Calendar", title: "This week", heading: "October 2026", lines: [
            "Monday      09:30  Planning                  Room 4", "Tuesday     14:00  Dentist                   Main Street",
            "Wednesday   11:00  Offsite budget review     Video call", "Thursday    10:00  Design review             Room 2",
            "Friday      16:30  Team demo                 Auditorium",
        ], monospaced: false),
    ],
]

func draw(_ scene: Scene, variant: Int) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)

    let sky = [NSColor(red: 0.16, green: 0.20, blue: 0.45, alpha: 1), NSColor(red: 0.45, green: 0.22, blue: 0.50, alpha: 1)]
    NSGradient(colors: sky)!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 35)

    NSColor(white: 0.12, alpha: 0.55).setFill()
    NSRect(x: 0, y: 0, width: width, height: 28).fill()
    func text(_ string: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = .white, mono: Bool = false) {
        let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
        string.draw(at: NSPoint(x: x, y: y), withAttributes: [.font: font, .foregroundColor: color])
    }
    text(scene.app, 40, 6, size: 14, weight: .bold)
    text("File   Edit   View   Window   Help", 120, 6, size: 14)
    text("Tue 13 Oct", CGFloat(width) - 130, 6, size: 14)

    let window = NSRect(x: 170, y: 70, width: 1388, height: 900)
    let dark = scene.monospaced
    (dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.97, alpha: 1)).setFill()
    NSBezierPath(roundedRect: window, xRadius: 12, yRadius: 12).fill()
    (dark ? NSColor(white: 0.20, alpha: 1) : NSColor(white: 0.90, alpha: 1)).setFill()
    NSBezierPath(roundedRect: NSRect(x: window.minX, y: window.minY, width: window.width, height: 44), xRadius: 12, yRadius: 12).fill()
    for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: window.minX + 18 + CGFloat(i) * 22, y: window.minY + 15, width: 13, height: 13)).fill()
    }
    let ink = dark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.12, alpha: 1)
    text(scene.title, window.midX - CGFloat(scene.title.count) * 4, window.minY + 13, size: 15, weight: .semibold, color: ink)
    text(scene.heading, window.minX + 60, window.minY + 90, size: 34, weight: .bold, color: ink, mono: dark)
    for (i, line) in scene.lines.enumerated() {
        text(line, window.minX + 60, window.minY + 170 + CGFloat(i) * 56, size: dark ? 24 : 22, color: ink.withAlphaComponent(0.9), mono: dark)
    }
    if variant % 2 == 1 {
        NSColor.systemBlue.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: window.minX + 40, y: window.minY + 150 + CGFloat(variant % scene.lines.count) * 56, width: 1000, height: 44), xRadius: 6, yRadius: 6).fill()
    }
    NSGraphicsContext.current = nil
    return rep.cgImage!
}

func relativePath(for date: Date, ext: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd/HHmmss"
    return formatter.string(from: date) + "." + ext
}

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    print("usage: demo-data <output dir> <yyyy-MM-dd>")
    exit(1)
}
let root = URL(fileURLWithPath: arguments[1], isDirectory: true)
let dayFormatter = DateFormatter()
dayFormatter.locale = Locale(identifier: "en_US_POSIX")
dayFormatter.dateFormat = "yyyy-MM-dd"
guard let day = dayFormatter.date(from: arguments[2]) else { print("bad date"); exit(1) }

try FileManager.default.createDirectory(at: root.appendingPathComponent("frames"), withIntermediateDirectories: true)
let db = try Database(path: root.appendingPathComponent("index.sqlite").path)

let schedule: [(start: Int, minutes: Int, app: String)] = [
    (9 * 60, 40, "Mail"), (9 * 60 + 40, 50, "Safari"), (10 * 60 + 30, 40, "Notes"), (11 * 60 + 10, 75, "Terminal"),
    (12 * 60 + 25, 35, "Safari"), (13 * 60, 25, "Mail"), (13 * 60 + 25, 45, "Calendar"), (14 * 60 + 10, 50, "Notes"),
    (15 * 60, 50, "Safari"), (15 * 60 + 50, 30, "Mail"), (16 * 60 + 20, 70, "Terminal"),
]
var count = 0
for block in schedule {
    let variants = scenes[block.app]!
    var minute = block.start
    var index = 0
    while minute < block.start + block.minutes {
        let date = day.addingTimeInterval(Double(minute) * 60 + Double((index * 17) % 40))
        let scene = variants[index / 3 % variants.count]
        let image = draw(scene, variant: index)
        let (data, ext) = try Capturer.encode(image)
        let path = relativePath(for: date, ext: ext)
        let url = root.appendingPathComponent("frames").appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        let ocr = OCR.recognize(image)
        _ = try await db.insert(date: date, app: scene.app, title: scene.title, path: path, text: ocr.text, boxes: WordBox.pack(ocr.words))
        minute += 2
        index += 1
        count += 1
    }
}
print("wrote \(count) frames to \(root.path)")
