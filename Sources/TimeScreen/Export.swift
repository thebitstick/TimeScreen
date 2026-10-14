import AppKit
import ImageIO
import UniformTypeIdentifiers

enum Transcript {
    static func fileName(for frame: Frame, ext: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HHmmss"
        return formatter.string(from: frame.date) + (frame.display > 0 ? "-d\(frame.display)" : "") + "." + ext
    }

    static func markdown(title: String, frames: [Frame], texts: [Int64: String]) -> String {
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var out = "# \(title)\n"
        for frame in frames {
            out += "\n## \(time.string(from: frame.date)) · \(frame.app)"
            if !frame.title.isEmpty { out += " — \(frame.title)" }
            if frame.display > 0 { out += " (display \(frame.display + 1))" }
            out += "\n"
            let text = (texts[frame.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                out += "\n" + text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }.joined(separator: "\n") + "\n"
            }
        }
        return out
    }

    static func plainText(of frame: Frame, text: String) -> String {
        var header = "\(frame.date.formatted(date: .complete, time: .standard))\n\(frame.app)"
        if !frame.title.isEmpty { header += " — \(frame.title)" }
        return header + "\n\n" + text
    }
}

@MainActor
enum Exporter {
    nonisolated static func writePNG(from source: URL, to destination: URL) throws {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let target = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        CGImageDestinationAddImage(target, image, nil)
        guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
    }

    nonisolated static func writeDay(frames: [Frame], texts: [Int64: String], title: String, root: URL, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for frame in frames {
            let source = root.appendingPathComponent(frame.path)
            let target = folder.appendingPathComponent(Transcript.fileName(for: frame, ext: source.pathExtension))
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.copyItem(at: source, to: target)
        }
        try Transcript.markdown(title: title, frames: frames, texts: texts)
            .write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
    }

    static func saveImage(of frame: Frame, root: URL, window: NSWindow?, done: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "TimeScreen \(stamp(frame.date)).png"
        run(panel, in: window) { url in
            do {
                try writePNG(from: root.appendingPathComponent(frame.path), to: url)
                done("Saved image")
            } catch {
                done("Couldn't save the image")
            }
        }
    }

    static func copyImage(of frame: Frame, root: URL) -> String {
        guard let image = NSImage(contentsOf: root.appendingPathComponent(frame.path)) else { return "Couldn't copy the image" }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        return "Copied image"
    }

    static func saveText(of frame: Frame, text: String, window: NSWindow?, done: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "TimeScreen \(stamp(frame.date)).txt"
        run(panel, in: window) { url in
            do {
                try Transcript.plainText(of: frame, text: text).write(to: url, atomically: true, encoding: .utf8)
                done("Saved text")
            } catch {
                done("Couldn't save the text")
            }
        }
    }

    static func saveTranscript(frames: [Frame], texts: [Int64: String], title: String, window: NSWindow?, done: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(title).md"
        run(panel, in: window) { url in
            do {
                try Transcript.markdown(title: title, frames: frames, texts: texts).write(to: url, atomically: true, encoding: .utf8)
                done("Exported \(frames.count) \(frames.count == 1 ? "result" : "results")")
            } catch {
                done("Couldn't export")
            }
        }
    }

    static func exportDay(frames: [Frame], texts: [Int64: String], title: String, root: URL, window: NSWindow?, done: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to put the exported folder."
        run(panel, in: window) { parent in
            let folder = parent.appendingPathComponent(title, isDirectory: true)
            Task.detached(priority: .utility) {
                do {
                    try writeDay(frames: frames, texts: texts, title: title, root: root, into: folder)
                    await MainActor.run { done("Exported \(frames.count) frames") }
                } catch {
                    await MainActor.run { done("Couldn't export") }
                }
            }
        }
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return formatter.string(from: date)
    }

    private static func run(_ panel: NSSavePanel, in window: NSWindow?, completion: @escaping (URL) -> Void) {
        let handler: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url { completion(url) }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) } else { panel.begin(completionHandler: handler) }
    }
}
