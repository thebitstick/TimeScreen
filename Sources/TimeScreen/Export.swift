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

enum ExportFormat: String, CaseIterable {
    case mostCompatible, highEfficiency, bestQuality

    static let preferenceKey = "exportFormat"

    static var saved: ExportFormat {
        get { UserDefaults.standard.string(forKey: preferenceKey).flatMap(ExportFormat.init) ?? .mostCompatible }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: preferenceKey) }
    }

    var title: String {
        switch self {
        case .mostCompatible: "Most Compatible (JPEG)"
        case .highEfficiency: "High Efficiency (HEIC)"
        case .bestQuality: "Best Quality (PNG)"
        }
    }

    var fileExtension: String {
        switch self {
        case .mostCompatible: "jpg"
        case .highEfficiency: "heic"
        case .bestQuality: "png"
        }
    }

    var type: UTType {
        switch self {
        case .mostCompatible: .jpeg
        case .highEfficiency: .heic
        case .bestQuality: .png
        }
    }

    /// Nil for PNG, which is lossless.
    var quality: Double? {
        switch self {
        case .mostCompatible: 0.9
        case .highEfficiency: 0.8
        case .bestQuality: nil
        }
    }

    func matches(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .mostCompatible: return ext == "jpg" || ext == "jpeg"
        case .highEfficiency: return ext == "heic"
        case .bestQuality: return ext == "png"
        }
    }
}

enum ImageEncoding {
    /// Copies the file untouched when it is already in `format`; otherwise decodes and re-encodes it.
    static func write(_ source: URL, as format: ExportFormat, to destination: URL) throws {
        if format.matches(source) {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
            return
        }
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil),
              let target = CGImageDestinationCreateWithURL(destination as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let options = format.quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(target, image, options)
        guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
    }
}

@MainActor
final class FormatAccessory: NSObject {
    let view: NSView
    private let popup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let onChange: (ExportFormat) -> Void

    private(set) var format: ExportFormat

    init(onChange: @escaping (ExportFormat) -> Void = { _ in }) {
        self.onChange = onChange
        format = ExportFormat.saved
        let label = NSTextField(labelWithString: "Image format:")
        popup.addItems(withTitles: ExportFormat.allCases.map(\.title))
        popup.selectItem(at: ExportFormat.allCases.firstIndex(of: format) ?? 0)
        let stack = NSStackView(views: [label, popup])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        view = stack
        super.init()
        popup.target = self
        popup.action = #selector(changed)
    }

    @objc private func changed() {
        format = ExportFormat.allCases[popup.indexOfSelectedItem]
        ExportFormat.saved = format
        onChange(format)
    }
}

@MainActor
enum Exporter {
    nonisolated static func writeDay(frames: [Frame], texts: [Int64: String], title: String, root: URL, format: ExportFormat, into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for frame in frames {
            let source = root.appendingPathComponent(frame.path)
            try ImageEncoding.write(source, as: format, to: folder.appendingPathComponent(Transcript.fileName(for: frame, ext: format.fileExtension)))
        }
        try Transcript.markdown(title: title, frames: frames, texts: texts)
            .write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)
    }

    static func saveImage(of frame: Frame, root: URL, window: NSWindow?, done: @escaping (String) -> Void) {
        let panel = NSSavePanel()
        let base = "TimeScreen \(stamp(frame.date))"
        let accessory = FormatAccessory { format in
            panel.allowedContentTypes = [format.type]
            panel.nameFieldStringValue = base + "." + format.fileExtension
        }
        panel.accessoryView = accessory.view
        panel.allowedContentTypes = [accessory.format.type]
        panel.nameFieldStringValue = base + "." + accessory.format.fileExtension
        run(panel, in: window) { url in
            do {
                try ImageEncoding.write(root.appendingPathComponent(frame.path), as: accessory.format, to: url)
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
        let accessory = FormatAccessory()
        panel.accessoryView = accessory.view
        run(panel, in: window) { parent in
            let folder = parent.appendingPathComponent(title, isDirectory: true)
            let format = accessory.format
            Task.detached(priority: .utility) {
                do {
                    try writeDay(frames: frames, texts: texts, title: title, root: root, format: format, into: folder)
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
