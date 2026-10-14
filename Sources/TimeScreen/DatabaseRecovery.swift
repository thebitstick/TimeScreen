import Foundation
import SQLite3

struct OpenedStore {
    let database: Database
    let framesRoot: URL
    /// Set when the normal store could not be used; shown to the person at launch.
    let notice: String?
}

enum DatabaseRecovery {
    /// Opens the index in `support`. A damaged index is moved aside and replaced by a fresh one (the screenshots stay on disk),
    /// and if even that fails the app runs from a temporary folder rather than refusing to start.
    static func open(support: URL, now: Date = Date()) -> OpenedStore {
        let fm = FileManager.default
        let frames = support.appendingPathComponent("frames", isDirectory: true)
        let index = support.appendingPathComponent("index.sqlite")
        var notice: String?

        if (try? fm.createDirectory(at: frames, withIntermediateDirectories: true)) != nil {
            if fm.fileExists(atPath: index.path), !isHealthy(path: index.path) {
                let saved = quarantine(index, now: now)
                notice = "TimeScreen's search index was damaged. The old index was saved as \(saved.lastPathComponent) and a new one was started. " +
                    "Your screenshots are untouched, but older ones won't appear in search."
            }
            if let database = try? Database(path: index.path) {
                return OpenedStore(database: database, framesRoot: frames, notice: notice)
            }
            if fm.fileExists(atPath: index.path) {
                let saved = quarantine(index, now: now)
                notice = "TimeScreen couldn't open its search index. It was saved as \(saved.lastPathComponent) and a new one was started."
                if let database = try? Database(path: index.path) {
                    return OpenedStore(database: database, framesRoot: frames, notice: notice)
                }
            }
        }

        let fallback = fm.temporaryDirectory.appendingPathComponent("TimeScreen-recovery", isDirectory: true)
        let fallbackFrames = fallback.appendingPathComponent("frames", isDirectory: true)
        try? fm.createDirectory(at: fallbackFrames, withIntermediateDirectories: true)
        let database = (try? Database(path: fallback.appendingPathComponent("index.sqlite").path)) ?? (try! Database(path: ":memory:"))
        return OpenedStore(database: database, framesRoot: fallbackFrames,
                           notice: "TimeScreen couldn't open its data folder, so it is recording to a temporary location that macOS may clear. " +
                               "Check that \(support.path) is writable.")
    }

    static func isHealthy(path: String) -> Bool {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(handle); return false }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "PRAGMA quick_check", -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return false }
        return String(cString: text) == "ok"
    }

    private static func quarantine(_ index: URL, now: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let saved = index.deletingLastPathComponent().appendingPathComponent("index.damaged-\(formatter.string(from: now)).sqlite")
        let fm = FileManager.default
        try? fm.moveItem(at: index, to: saved)
        for suffix in ["-wal", "-shm"] { try? fm.removeItem(atPath: index.path + suffix) }
        return saved
    }
}
