import CoreGraphics

enum Signature {
    static let width = 64
    static let height = 36

    static func make(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    static func isDuplicate(_ a: [UInt8], _ b: [UInt8], minChangedCells: Int = 3) -> Bool {
        guard a.count == b.count else { return false }
        var changed = 0
        for i in a.indices where abs(Int(a[i]) - Int(b[i])) > 4 {
            changed += 1
            if changed >= minChangedCells { return false }
        }
        return true
    }
}
