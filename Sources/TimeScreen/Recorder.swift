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
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var skipReason: SkipReason?

    private var loop: Task<Void, Never>?
    private var resumeTimer: Task<Void, Never>?
    private var lastSignatures: [Int: [UInt8]] = [:]
    private var suspensions = Set<String>()
    private var lastPrune = Date.distantPast
    private var lastCapCheck = Date.distantPast
    private var lastCompact = Date.distantPast

    private init() {
        let support = ProcessInfo.processInfo.environment["TIMESCREEN_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        Task {
            await refreshToday()
            await backfillBundles()
            await Storage.removeOrphans(root: framesRoot, db: db)
        }
    }

    /// Frames from before bundle identifiers were stored get them from what is known about each app name.
    private func backfillBundles() async {
        guard let apps = try? await db.appsMissingBundle() else { return }
        for app in apps {
            if let bundle = AppIcons.shared.bundleIdentifier(for: app) { try? await db.setBundle(bundle, forApp: app) }
        }
    }

    func setRecording(_ on: Bool) {
        resumeTimer?.cancel()
        pausedUntil = nil
        isRecording = on
        UserDefaults.standard.set(on, forKey: Prefs.recording)
        startLoop()
    }

    var menuBarSymbol: String {
        MenuBarState.symbol(hasPermission: hasPermission, isRecording: isRecording, skip: skipReason, hasError: lastError != nil)
    }

    var menuBarDescription: String {
        MenuBarState.description(hasPermission: hasPermission, isRecording: isRecording, skip: skipReason, hasError: lastError != nil)
    }

    func frames(lastMinutes minutes: Int) async -> [Frame] {
        let now = Date()
        return (try? await db.frames(from: now.addingTimeInterval(-Double(minutes) * 60), to: now.addingTimeInterval(60))) ?? []
    }

    func delete(_ frames: [Frame]) async {
        guard !frames.isEmpty else { return }
        try? await db.delete(ids: frames.map(\.id))
        await Storage.removeFiles(frames.map(\.path), under: framesRoot)
        revision += 1
        await refreshToday()
    }

    func setTimelineOpen(_ open: Bool) {
        if open { suspensions.insert("timeline") } else { suspensions.remove("timeline") }
    }

    func pause(for seconds: TimeInterval) {
        resumeTimer?.cancel()
        isRecording = false
        pausedUntil = Date().addingTimeInterval(seconds)
        startLoop()
        resumeTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            setRecording(UserDefaults.standard.bool(forKey: Prefs.recording))
        }
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

    func diskUsage() async -> Int64 { await Storage.usage(of: framesRoot) }

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
        skipReason = nil
        hasPermission = CGPreflightScreenCaptureAccess()
        if Date().timeIntervalSince(lastPrune) > 3600 { await prune() }
        if Date().timeIntervalSince(lastCapCheck) > 600 { await enforceStorageCap() }
        guard hasPermission, suspensions.isEmpty else { return }

        let defaults = UserDefaults.standard
        let environmentSkip = SkipReason.power(onBattery: Power.isOnBattery, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                               pauseOnBattery: defaults.bool(forKey: Prefs.pauseOnBattery),
                                               pauseInLowPower: defaults.bool(forKey: Prefs.pauseInLowPower))
            ?? SkipReason.disk(freeBytes: Disk.freeBytes(at: framesRoot))
        if let environmentSkip {
            skipReason = environmentSkip
            return
        }

        do {
            let targets = try await Capturer.targets(all: UserDefaults.standard.bool(forKey: Prefs.allDisplays))
            let windows = Windows.frontToBack()
            let front = NSWorkspace.shared.frontmostApplication
            let excluded = Prefs.excludedBundleIDs()
            let skipPrivate = UserDefaults.standard.bool(forKey: Prefs.skipPrivate)
            let privateKeywords = Prefs.privateTitleKeywords()
            let now = Date()
            let root = framesRoot
            let ocrEnabled = UserDefaults.standard.bool(forKey: Prefs.ocr)
            let db = self.db

            var privateSkips = 0
            defer { if privateSkips == targets.count { skipReason = .privateWindow } }
            for target in targets {
                let top = Windows.topWindow(in: windows, on: target.bounds)
                let owner = top.flatMap { NSRunningApplication(processIdentifier: $0.pid) } ?? front
                let bundleID = owner?.bundleIdentifier ?? ""
                let title = top.map { Windows.title(of: $0, in: windows, on: target.bounds) } ?? ""
                let showsPrivate = skipPrivate && Windows.showsPrivateWindow(windows, on: target.bounds, keywords: privateKeywords)
                if bundleID == Bundle.main.bundleIdentifier || excluded.contains(bundleID) || showsPrivate {
                    lastSignatures[target.index] = nil
                    if showsPrivate { privateSkips += 1 }
                    continue
                }
                let app = owner?.localizedName ?? "Unknown"
                AppIcons.shared.remember(owner)

                let image = try await Capturer.capture(target)
                guard suspensions.isEmpty else { return }
                let signature = await Task.detached { Signature.make(image) }.value
                if let last = lastSignatures[target.index], Signature.isDuplicate(last, signature) { continue }
                lastSignatures[target.index] = signature

                try await Task.detached(priority: .utility) {
                    let (data, ext) = try Capturer.encode(image)
                    let relative = Recorder.relativePath(for: now, display: target.index, ext: ext)
                    let url = root.appendingPathComponent(relative)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url)
                    let ocr = ocrEnabled ? OCR.recognize(image) : OCRResult()
                    try await db.insert(date: now, app: app, title: title, path: relative, text: ocr.text,
                                        boxes: WordBox.pack(ocr.words), display: target.index, bundle: bundleID)
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
        await Storage.removeFiles(paths, under: framesRoot)
        revision += 1
    }

    private func enforceStorageCap() async {
        lastCapCheck = Date()
        let gigabytes = UserDefaults.standard.integer(forKey: Prefs.maxStorageGB)
        guard gigabytes > 0, await Storage.enforce(cap: Int64(gigabytes) * 1_000_000_000, root: framesRoot, db: db) else { return }
        revision += 1
        await refreshToday()
    }

    nonisolated static func relativePath(for date: Date, display: Int = 0, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd/HHmmss"
        return formatter.string(from: date) + (display > 0 ? "-d\(display)" : "") + "." + ext
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
