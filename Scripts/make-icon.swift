import AppKit

func draw(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let u = size / 1024

    // macOS icon grid: the squircle fills 824/1024 of the canvas.
    let tile = CGRect(x: 100 * u, y: 100 * u, width: 824 * u, height: 824 * u)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * u, yRadius: 185 * u)

    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12 * u)
    shadow.shadowBlurRadius = 24 * u
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()
    let gradient = NSGradient(colors: [NSColor(red: 0.07, green: 0.09, blue: 0.22, alpha: 1),
                                       NSColor(red: 0.20, green: 0.22, blue: 0.62, alpha: 1)])!
    gradient.draw(in: tile, angle: -60)

    let screenW = 430 * u, screenH = 290 * u
    let baseX = 512 * u + 70 * u, baseY = 450 * u
    for i in (0..<4).reversed() {
        let step = CGFloat(i)
        let rect = CGRect(x: baseX - screenW / 2 - step * 66 * u, y: baseY - screenH / 2 + step * 4 * u,
                          width: screenW, height: screenH)
        let path = NSBezierPath(roundedRect: rect, xRadius: 34 * u, yRadius: 34 * u)
        NSColor.white.withAlphaComponent(i == 0 ? 0.96 : 0.36 - step * 0.07).setFill()
        path.fill()
        if i == 0 {
            NSColor(red: 0.20, green: 0.22, blue: 0.62, alpha: 0.5).setFill()
            for (n, width) in [300, 240, 270].enumerated() {
                let line = CGRect(x: rect.minX + 44 * u, y: rect.maxY - (78 + CGFloat(n) * 58) * u,
                                  width: CGFloat(width) * u, height: 20 * u)
                NSBezierPath(roundedRect: line, xRadius: 10 * u, yRadius: 10 * u).fill()
            }
        }
    }

    let headX = baseX
    let screenTop = baseY + screenH / 2
    NSColor(red: 1.0, green: 0.36, blue: 0.40, alpha: 1).setFill()
    let stem = CGRect(x: headX - 5 * u, y: screenTop + 56 * u, width: 10 * u, height: 90 * u)
    NSBezierPath(roundedRect: stem, xRadius: 5 * u, yRadius: 5 * u).fill()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: headX - 30 * u, y: screenTop + 62 * u))
    head.line(to: CGPoint(x: headX + 30 * u, y: screenTop + 62 * u))
    head.line(to: CGPoint(x: headX, y: screenTop + 14 * u))
    head.close()
    head.fill()
    ctx.restoreGState()

    ctx.saveGState()
    tilePath.addClip()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 2 * u, dy: 2 * u), xRadius: 183 * u, yRadius: 183 * u)
    rim.lineWidth = 4 * u
    rim.stroke()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = "build/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = CGFloat(base * scale)
        let png = draw(size: pixels).representation(using: .png, properties: [:])!
        try png.write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"))
    }
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
