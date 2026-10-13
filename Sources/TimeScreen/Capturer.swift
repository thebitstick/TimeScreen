import CoreGraphics
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import Vision

enum CaptureError: Error, LocalizedError {
    case noDisplay, encode
    var errorDescription: String? {
        switch self {
        case .noDisplay: return "No display available to capture"
        case .encode: return "Could not encode the screenshot"
        }
    }
}

enum Capturer {
    /// Index 0 is the main display; the others follow from left to right.
    static func captureDisplays(all: Bool) async throws -> [(index: Int, image: CGImage)] {
        let content = try await SCShareableContent.current
        let main = CGMainDisplayID()
        let ordered = content.displays.sorted {
            ($0.displayID == main ? -Double.infinity : $0.frame.minX) < ($1.displayID == main ? -Double.infinity : $1.frame.minX)
        }
        guard !ordered.isEmpty else { throw CaptureError.noDisplay }
        var captured: [(Int, CGImage)] = []
        for (index, display) in ordered.prefix(all ? ordered.count : 1).enumerated() {
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            config.width = Int(CGFloat(display.width) * scale)
            config.height = Int(CGFloat(display.height) * scale)
            config.showsCursor = true
            captured.append((index, try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)))
        }
        return captured
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
}

enum OCR {
    static func recognize(_ image: CGImage) -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return OCRResult() }

        var lines: [String] = []
        var words: [WordBox] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            lines.append(line)
            line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: .byWords) { word, range, _, _ in
                guard let word, let box = try? candidate.boundingBox(for: range)?.boundingBox else { return }
                words.append(WordBox(t: word.lowercased(), x: Float(box.minX), y: Float(box.minY),
                                     w: Float(box.width), h: Float(box.height)))
            }
        }
        return OCRResult(text: lines.joined(separator: "\n"), words: words)
    }
}
