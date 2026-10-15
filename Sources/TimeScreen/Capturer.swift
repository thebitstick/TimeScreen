import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

enum CaptureError: Error, LocalizedError {
    case noDisplay, encode
    var errorDescription: String? {
        switch self {
        case .noDisplay: return String(localized: "No display available to capture")
        case .encode: return String(localized: "Could not encode the screenshot")
        }
    }
}

enum Capturer {
    struct Target {
        let index: Int
        let display: SCDisplay
        var bounds: CGRect { CGDisplayBounds(display.displayID) }
    }

    /// Index 0 is the main display; the others follow from left to right.
    static func targets(all: Bool) async throws -> [Target] {
        let content = try await SCShareableContent.current
        let main = CGMainDisplayID()
        let ordered = content.displays.sorted {
            ($0.displayID == main ? -Double.infinity : $0.frame.minX) < ($1.displayID == main ? -Double.infinity : $1.frame.minX)
        }
        guard !ordered.isEmpty else { throw CaptureError.noDisplay }
        return ordered.prefix(all ? ordered.count : 1).enumerated().map { Target(index: $0.offset, display: $0.element) }
    }

    static func capture(_ target: Target) async throws -> CGImage {
        let filter = SCContentFilter(display: target.display, excludingWindows: [])
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(CGFloat(target.display.width) * scale)
        config.height = Int(CGFloat(target.display.height) * scale)
        config.showsCursor = true
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func encode(_ image: CGImage, quality: Double = 0.5) throws -> (data: Data, ext: String) {
        for (type, ext) in [(UTType.heic, "heic"), (UTType.jpeg, "jpg")] {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            if CGImageDestinationFinalize(destination) { return (data as Data, ext) }
        }
        throw CaptureError.encode
    }
}

struct OCRResult {
    var text = ""
    var words: [WordBox] = []
    var failure: Error?
}

struct RecognitionHealth {
    static let limit = 3
    static var warning: String { String(localized: "Text recognition stopped working, so new screenshots can't be searched. Quit and reopen TimeScreen.") }

    private(set) var failures = 0
    var isFailing: Bool { failures >= Self.limit }

    mutating func record(failed: Bool) {
        failures = failed ? failures + 1 : 0
    }
}

enum OCR {
    static func recognize(_ image: CGImage, perform: (CGImage, VNRecognizeTextRequest) throws -> Void = { image, request in
        try VNImageRequestHandler(cgImage: image).perform([request])
    }) -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do {
            do {
                try perform(image, request)
            } catch {
                try perform(image, request)
            }
        } catch {
            NSLog("TimeScreen: text recognition failed: %@", String(describing: error))
            return OCRResult(failure: error)
        }

        var lines: [String] = []
        var words: [WordBox] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            lines.append(line)
            line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: .byWords) { word, range, _, _ in
                guard let word, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return }
                words.append(WordBox(t: word, x: Float(box.minX), y: Float(box.minY),
                                     w: Float(box.width), h: Float(box.height)))
            }
        }
        return OCRResult(text: lines.joined(separator: "\n"), words: words)
    }
}
