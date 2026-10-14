import Foundation
import SQLite3

struct Frame: Identifiable, Hashable {
    let id: Int64
    let date: Date
    let app: String
    let title: String
    let path: String
    var display = 0
}

struct SearchHit: Identifiable, Hashable {
    let frame: Frame
    let snippet: String
    var id: Int64 { frame.id }
}

enum DatabaseError: Error, LocalizedError {
    case sqlite(String)
    var errorDescription: String? {
        switch self { case .sqlite(let message): return message }
    }
}

/// One recognized word with its normalized position (Vision coordinates: origin bottom-left, 0...1).
struct WordBox: Codable, Hashable {
    let t: String
    let x: Float, y: Float, w: Float, h: Float

    init(t: String, x: Float, y: Float, w: Float, h: Float) {
        self.t = t; self.x = x; self.y = y; self.w = w; self.h = h
    }

    // Encoded as [text, x, y, w, h] arrays: compact before compression.
    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        t = try c.decode(String.self)
        x = try c.decode(Float.self); y = try c.decode(Float.self)
        w = try c.decode(Float.self); h = try c.decode(Float.self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(t)
        for value in [x, y, w, h] { try c.encode((value * 1000).rounded() / 1000) }
    }

    static func pack(_ words: [WordBox]) -> Data? {
        guard !words.isEmpty, let json = try? JSONEncoder().encode(words) else { return nil }
        return try? (json as NSData).compressed(using: .lzfse) as Data
    }

    static func unpack(_ data: Data?) -> [WordBox] {
        guard let data, let json = try? (data as NSData).decompressed(using: .lzfse) as Data else { return [] }
        return (try? JSONDecoder().decode([WordBox].self, from: json)) ?? []
    }

    var rect: CGRect { CGRect(x: CGFloat(x), y: CGFloat(1 - y - h), width: CGFloat(w), height: CGFloat(h)) }

    static func text(of words: [WordBox]) -> String {
        let top = { (word: WordBox) in word.y + word.h / 2 }
        var lines: [[WordBox]] = []
        for word in words.sorted(by: { top($0) > top($1) }) {
            if let last = lines.last?.last, abs(top(last) - top(word)) < Float(min(last.h, word.h)) / 2 {
                lines[lines.count - 1].append(word)
            } else {
                lines.append([word])
            }
        }
        return lines.map { $0.sorted { $0.x < $1.x }.map(\.t).joined(separator: " ") }.joined(separator: "\n")
    }

    static func matches(_ boxes: [WordBox], terms: [String]) -> [WordBox] {
        guard !terms.isEmpty else { return [] }
        return boxes.filter { box in terms.contains { box.t.contains($0) } }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor Database {
    private enum Value {
        case text(String), int(Int64), double(Double), blob(Data), null
    }

    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            sqlite3_close(db)
            throw DatabaseError.sqlite(message)
        }
        for sql in [
            "PRAGMA journal_mode=WAL",
            "CREATE TABLE IF NOT EXISTS frames(id INTEGER PRIMARY KEY, ts REAL NOT NULL, app TEXT NOT NULL, title TEXT NOT NULL, path TEXT NOT NULL)",
            "CREATE INDEX IF NOT EXISTS frames_ts ON frames(ts)",
            "CREATE TABLE IF NOT EXISTS boxes(frame_id INTEGER PRIMARY KEY, data BLOB NOT NULL)",
            "CREATE VIRTUAL TABLE IF NOT EXISTS frames_fts USING fts5(text, app, title, tokenize='unicode61 remove_diacritics 2')",
        ] {
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                let message = String(cString: sqlite3_errmsg(db))
                sqlite3_close(db)
                throw DatabaseError.sqlite(message)
            }
        }
        // Added after v0.1; fails harmlessly once the column exists.
        sqlite3_exec(db, "ALTER TABLE frames ADD COLUMN compacted INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        sqlite3_exec(db, "ALTER TABLE frames ADD COLUMN display INTEGER NOT NULL DEFAULT 0", nil, nil, nil)
        handle = db
    }

    deinit { sqlite3_close(handle) }


    @discardableResult
    func insert(date: Date, app: String, title: String, path: String, text: String, boxes: Data? = nil, display: Int = 0) throws -> Int64 {
        try run("INSERT INTO frames(ts, app, title, path, display) VALUES(?,?,?,?,?)",
                [.double(date.timeIntervalSince1970), .text(app), .text(title), .text(path), .int(Int64(display))])
        let id = sqlite3_last_insert_rowid(handle)
        try run("INSERT INTO frames_fts(rowid, text, app, title) VALUES(?,?,?,?)",
                [.int(id), .text(text), .text(app), .text(title)])
        if let boxes { try run("INSERT INTO boxes(frame_id, data) VALUES(?,?)", [.int(id), .blob(boxes)]) }
        return id
    }

    func prune(before date: Date) throws -> [String] {
        let cutoff = Value.double(date.timeIntervalSince1970)
        let paths = try rows("SELECT path FROM frames WHERE ts < ?", [cutoff]) { Self.text($0, 0) }
        try run("DELETE FROM frames_fts WHERE rowid IN (SELECT id FROM frames WHERE ts < ?)", [cutoff])
        try run("DELETE FROM boxes WHERE frame_id IN (SELECT id FROM frames WHERE ts < ?)", [cutoff])
        try run("DELETE FROM frames WHERE ts < ?", [cutoff])
        return paths
    }

    func oldestFrames(limit: Int) throws -> [Frame] {
        try rows("SELECT id, ts, app, title, path, display FROM frames ORDER BY ts LIMIT ?", [.int(Int64(limit))]) { Self.frame($0) }
    }

    func delete(ids: [Int64]) throws {
        for id in ids {
            try run("DELETE FROM frames_fts WHERE rowid = ?", [.int(id)])
            try run("DELETE FROM boxes WHERE frame_id = ?", [.int(id)])
            try run("DELETE FROM frames WHERE id = ?", [.int(id)])
        }
    }

    func deleteAll() throws {
        try run("DELETE FROM frames_fts", [])
        try run("DELETE FROM boxes", [])
        try run("DELETE FROM frames", [])
    }

    func framesToCompact(before date: Date, limit: Int) throws -> [Frame] {
        try rows("SELECT id, ts, app, title, path, display FROM frames WHERE compacted = 0 AND ts < ? ORDER BY ts LIMIT ?",
                 [.double(date.timeIntervalSince1970), .int(Int64(limit))], map: Self.frame)
    }

    func markCompacted(id: Int64, path: String) throws {
        try run("UPDATE frames SET compacted = 1, path = ? WHERE id = ?", [.text(path), .int(id)])
    }

    func boxes(for frameID: Int64) throws -> Data? {
        try rows("SELECT data FROM boxes WHERE frame_id = ?", [.int(frameID)]) { stmt in
            let count = Int(sqlite3_column_bytes(stmt, 0))
            guard count > 0, let bytes = sqlite3_column_blob(stmt, 0) else { return Data() }
            return Data(bytes: bytes, count: count)
        }.first
    }


    func frames(on day: Date) throws -> [Frame] {
        let (start, end) = Self.bounds(of: day)
        return try rows("SELECT id, ts, app, title, path, display FROM frames WHERE ts >= ? AND ts < ? ORDER BY ts",
                        [.double(start), .double(end)], map: Self.frame)
    }

    func frames(from start: Date, to end: Date) throws -> [Frame] {
        try rows("SELECT id, ts, app, title, path, display FROM frames WHERE ts >= ? AND ts < ? ORDER BY ts",
                 [.double(start.timeIntervalSince1970), .double(end.timeIntervalSince1970)], map: Self.frame)
    }

    func count(on day: Date) throws -> Int {
        let (start, end) = Self.bounds(of: day)
        return try rows("SELECT COUNT(*) FROM frames WHERE ts >= ? AND ts < ?",
                        [.double(start), .double(end)]) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    func days() throws -> [Date] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return try rows("SELECT DISTINCT date(ts, 'unixepoch', 'localtime') AS d FROM frames ORDER BY d DESC", []) {
            Self.text($0, 0)
        }.compactMap { formatter.date(from: $0) }
    }

    func apps() throws -> [(app: String, count: Int)] {
        try rows("SELECT app, COUNT(*) AS n FROM frames GROUP BY app ORDER BY n DESC", []) {
            (Self.text($0, 0), Int(sqlite3_column_int64($0, 1)))
        }
    }

    func search(_ query: String, app: String? = nil, from: Date? = nil, to: Date? = nil, limit: Int = 200) throws -> [SearchHit] {
        guard let match = Self.matchExpression(query) else { return [] }
        return try rows("""
            SELECT f.id, f.ts, f.app, f.title, f.path, f.display, snippet(frames_fts, 0, '', '', '…', 14)
            FROM frames_fts JOIN frames f ON f.id = frames_fts.rowid
            WHERE frames_fts MATCH ? AND (? IS NULL OR f.app = ?) AND (? IS NULL OR f.ts >= ?) AND (? IS NULL OR f.ts < ?)
            ORDER BY f.ts DESC LIMIT ?
            """, [.text(match), app.map(Value.text) ?? .null, app.map(Value.text) ?? .null,
                  from.map { Value.double($0.timeIntervalSince1970) } ?? .null, from.map { Value.double($0.timeIntervalSince1970) } ?? .null,
                  to.map { Value.double($0.timeIntervalSince1970) } ?? .null, to.map { Value.double($0.timeIntervalSince1970) } ?? .null,
                  .int(Int64(limit))]) {
            SearchHit(frame: Self.frame($0), snippet: Self.text($0, 6))
        }
    }

    nonisolated static func matchExpression(_ query: String) -> String? {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " ")
    }


    private nonisolated static func bounds(of day: Date) -> (Double, Double) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start.timeIntervalSince1970, end.timeIntervalSince1970)
    }

    private nonisolated static func text(_ stmt: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(stmt, column).map { String(cString: $0) } ?? ""
    }

    private nonisolated static func frame(_ stmt: OpaquePointer) -> Frame {
        Frame(id: sqlite3_column_int64(stmt, 0),
              date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1)),
              app: text(stmt, 2), title: text(stmt, 3), path: text(stmt, 4), display: Int(sqlite3_column_int(stmt, 5)))
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        for (i, value) in values.enumerated() {
            let index = Int32(i + 1)
            switch value {
            case .null: sqlite3_bind_null(stmt, index)
            case .text(let s): sqlite3_bind_text(stmt, index, s, -1, SQLITE_TRANSIENT)
            case .int(let n): sqlite3_bind_int64(stmt, index, n)
            case .double(let d): sqlite3_bind_double(stmt, index, d)
            case .blob(let data):
                _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), SQLITE_TRANSIENT) }
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func rows<T>(_ sql: String, _ values: [Value], map: (OpaquePointer) -> T) throws -> [T] {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            switch sqlite3_step(stmt) {
            case SQLITE_ROW: out.append(map(stmt))
            case SQLITE_DONE: return out
            default: throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }
}
