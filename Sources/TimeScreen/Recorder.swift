import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class Recorder: ObservableObject {
    static let shared = Recorder()

    let framesRoot: URL
    let db: Database

    @Published private(set) var isRecording = UserDefaults.standard.bool(forKey: Prefs.recording)
    @Published private(set) var hasPermission = CGPreflightScreenCaptureAccess()
    @Published private(set) var revision = 0
    @Published private(set) var framesToday = 0
    @Published private(set) var lastCapture: Date?
    @Published private(set) var lastError: String?

    private var loop: Task<Void, Never>?
    private var lastSignatures: [Int: [UInt8]] = [:]
    private var suspensions = Set<String>()
    private var lastPrune = Date.distantPast
    private var lastCompact = Date.distantPast

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TimeScreen", isDirectory: true)
        framesRoot = support.appendingPathComponent("frames", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: framesRoot, withIntermediateDirectories: true)
            db = try Database(path: support.appendingPathComponent("index.sqlite").path)
        } catch {
            fatalError("TimeScreen cannot open its data directory: \(error.localizedDescription)")
        }
    }

    func start() {
        observeSystemState()
        startLoop()
        Task { await refreshToday() }
    }

    func setRecording(_ on: Bool) {
        isRecording = on
        UserDefaults.standard.set(on, forKey: Prefs.recording)
        startLoop()
    }

    func requestPermission() {
        if !CGRequestScreenCaptureAccess() {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func deleteAll() async {
        try? await db.deleteAll()
        try? FileManager.default.removeItem(at: framesRoot)
        try? FileManager.default.createDirectory(at: framesRoot, withIntermediateDirectories: true)
        lastSignatures = [:]
        framesToday = 0
        revision += 1
    }

    func diskUsage() async -> Int64 {
        let root = framesRoot
        return await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
            var total: Int64 = 0
            while let url = files?.nextObject() as? URL {
                total += Int64((try? url.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0)
            }
            return total
        }.value
    }


    private func startLoop() {
        loop?.cancel()
        loop = nil
        guard isRecording else { return }
        loop = Task {
            while !Task.isCancelled {
                await tick()
                let seconds = max(1, UserDefaults.standard.double(forKey: Prefs.interval))
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        }
    }

    private func tick() async {
        hasPermission = CGPreflightScreenCaptureAccess()
        if Date().timeIntervalSince(lastPrune) > 3600 { await prune() }
        guard hasPermission, suspensions.isEmpty else { return }

        let front = NSWorkspace.shared.frontmostApplication
        let bundleID = front?.bundleIdentifier ?? ""
        if bundleID == Bundle.main.bundleIdentifier || Prefs.excludedBundleIDs().contains(bundleID) { return }
        let app = front?.localizedName ?? "Unknown"
        AppIcons.shared.remember(front)
        let title = front.map { Self.windowTitle(pid: $0.processIdentifier) } ?? ""

        do {
            let displays = try await Capturer.captureDisplays(all: UserDefaults.standard.bool(forKey: Prefs.allDisplays))
            let now = Date()
            let root = framesRoot
            let ocrEnabled = UserDefaults.standard.bool(forKey: Prefs.ocr)
            let db = self.db
            for (index, image) in displays {
                let signature = await Task.detached { Signature.make(image) }.value
                if let last = lastSignatures[index], Signature.isDuplicate(last, signature) { continue }
                lastSignatures[index] = signature

                try await Task.detached(priority: .utility) {
                    let (data, ext) = try Capturer.encode(image)
                    let relative = Recorder.relativePath(for: now, display: index, ext: ext)
                    let url = root.appendingPathComponent(relative)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url)
                    let ocr = ocrEnabled ? OCR.recognize(image) : OCRResult()
                    try await db.insert(date: now, app: app, title: title, path: relative, text: ocr.text,
                                        boxes: WordBox.pack(ocr.words), display: index)
                }.value
            }

            lastCapture = now
            lastError = nil
            revision += 1
            await refreshToday()
        } catch {
            lastError = error.localizedDescription
        }
        if Date().timeIntervalSince(lastCompact) > 60 { await compactOldFrames() }
    }

    private func compactOldFrames() async {
        lastCompact = Date()
        guard UserDefaults.standard.bool(forKey: Prefs.compactOld),
              let cutoff = Calendar.current.date(byAdding: .hour, value: -24, to: Date()),
              let frames = try? await db.framesToCompact(before: cutoff, limit: 40), !frames.isEmpty else { return }
        let root = framesRoot
        let db = self.db
        await Task.detached(priority: .background) {
            for frame in frames {
                let old = root.appendingPathComponent(frame.path)
                var newPath = frame.path
                if let small = Thumbnails.downscaled(old, maxPixel: 1728),
                   let (data, ext) = try? Capturer.encode(small, quality: 0.45) {
                    let candidate = Recorder.relativePath(for: frame.date, display: frame.display, ext: ext)
                    if (try? data.write(to: root.appendingPathComponent(candidate), options: .atomic)) != nil {
                        newPath = candidate
                        if candidate != frame.path { try? FileManager.default.removeItem(at: old) }
                    }
                }
                try? await db.markCompacted(id: frame.id, path: newPath)
            }
        }.value
    }

    private func refreshToday() async {
        framesToday = (try? await db.count(on: Date())) ?? framesToday
    }

    private func prune() async {
        lastPrune = Date()
        let days = UserDefaults.standard.integer(forKey: Prefs.retentionDays)
        guard days > 0, let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return }
        guard let paths = try? await db.prune(before: cutoff), !paths.isEmpty else { return }
        let root = framesRoot
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            for path in paths { try? fm.removeItem(at: root.appendingPathComponent(path)) }
            for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? ["x"]).isEmpty {
                try? fm.removeItem(at: dir)
            }
        }.value
        revision += 1
    }


    nonisolated static func relativePath(for date: Date, display: Int = 0, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd/HHmmss"
        return formatter.string(from: date) + (display > 0 ? "-d\(display)" : "") + "." + ext
    }

    private static func windowTitle(pid: pid_t) -> String {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return ""
        }
        // The list is ordered front to back, so the first normal window of the app is the one on top.
        for window in windows where (window[kCGWindowOwnerPID as String] as? pid_t) == pid && (window[kCGWindowLayer as String] as? Int) == 0 {
            if let name = window[kCGWindowName as String] as? String, !name.isEmpty { return name }
        }
        return ""
    }

    private func observeSystemState() {
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(off: Notification.Name, on: Notification.Name, reason: String)] = [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screen"),
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session"),
        ]
        for pair in pairs { observe(workspace, off: pair.off, on: pair.on, reason: pair.reason) }
        observe(DistributedNotificationCenter.default(), off: .init("com.apple.screenIsLocked"),
                on: .init("com.apple.screenIsUnlocked"), reason: "lock")
    }

    private func observe(_ center: NotificationCenter, off: Notification.Name, on: Notification.Name, reason: String) {
        center.addObserver(forName: off, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.suspensions.insert(reason) }
        }
        center.addObserver(forName: on, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.suspensions.remove(reason) }
        }
    }
}
