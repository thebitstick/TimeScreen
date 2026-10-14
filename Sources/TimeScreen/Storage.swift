import Foundation

enum Storage {
    static func usage(of root: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey]
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys)
            var total: Int64 = 0
            while let url = files?.nextObject() as? URL {
                total += Int64((try? url.resourceValues(forKeys: Set(keys)).totalFileAllocatedSize) ?? 0)
            }
            return total
        }.value
    }

    @discardableResult
    static func removeFiles(_ paths: [String], under root: URL) async -> Int64 {
        await Task.detached(priority: .utility) {
            let fm = FileManager.default
            var freed: Int64 = 0
            for path in paths {
                let url = root.appendingPathComponent(path)
                freed += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                try? fm.removeItem(at: url)
            }
            for dir in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            where ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? ["x"]).isEmpty {
                try? fm.removeItem(at: dir)
            }
            return freed
        }.value
    }

    private static func allocatedSize(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
    }

    /// Deletes the oldest frames until usage is back under 90% of `cap`. Returns whether anything was deleted.
    static func enforce(cap: Int64, root: URL, db: Database) async -> Bool {
        var remaining = await usage(of: root)
        guard remaining > cap else { return false }
        let target = Int64(Double(cap) * 0.9)
        var removedAny = false
        while remaining > target {
            guard let batch = try? await db.oldestFrames(limit: 200), !batch.isEmpty else { break }
            var doomed: [Frame] = []
            var freed: Int64 = 0
            for frame in batch where remaining - freed > target {
                freed += allocatedSize(root.appendingPathComponent(frame.path))
                doomed.append(frame)
            }
            await removeFiles(doomed.map(\.path), under: root)
            guard (try? await db.delete(ids: doomed.map(\.id))) != nil else { break }
            remaining -= freed
            removedAny = true
        }
        return removedAny
    }

    /// Screenshots whose index entry never got written (the app quit between the two) are deleted. Files younger than
    /// `age` are left alone, since a capture or compaction may be about to record them. If most files look orphaned, something
    /// else is wrong (a wrong folder, a replaced index), so nothing is deleted.
    @discardableResult
    static func removeOrphans(root: URL, db: Database, olderThan age: TimeInterval = 60) async -> Int {
        guard let known = try? await db.allPaths(), !known.isEmpty else { return 0 }
        return await Task.detached(priority: .utility) {
            let fm = FileManager.default
            let base = root.resolvingSymlinksInPath()
            let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
            guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: keys) else { return 0 }
            var total = 0
            var orphans: [URL] = []
            while let url = enumerator.nextObject() as? URL {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                      url.lastPathComponent != ".DS_Store" else { continue }
                total += 1
                let components = url.resolvingSymlinksInPath().pathComponents
                guard components.starts(with: base.pathComponents),
                      let modified = values.contentModificationDate, Date().timeIntervalSince(modified) > age else { continue }
                if !known.contains(components.dropFirst(base.pathComponents.count).joined(separator: "/")) { orphans.append(url) }
            }
            guard orphans.count * 2 <= total else { return 0 }
            for url in orphans { try? fm.removeItem(at: url) }
            for dir in (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            where ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? ["x"]).isEmpty {
                try? fm.removeItem(at: dir)
            }
            return orphans.count
        }.value
    }
}
