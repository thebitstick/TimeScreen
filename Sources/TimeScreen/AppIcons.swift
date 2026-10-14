import AppKit
import SwiftUI

@MainActor
final class AppIcons {
    static let shared = AppIcons()

    private var urlsByName: [String: URL]?
    private var icons: [String: NSImage] = [:]
    private var colors: [String: Color] = [:]
    private var bundlesByName: [String: String] = [:]

    func icon(for app: String) -> NSImage? {
        if let cached = icons[app] { return cached }
        guard let url = location(of: app) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 32, height: 32)
        icons[app] = icon
        return icon
    }

    func color(for app: String) -> Color {
        if let cached = colors[app] { return cached }
        let color = icon(for: app).flatMap(Self.averageColor) ?? Self.hashColor(app)
        colors[app] = color
        return color
    }

    func remember(_ app: NSRunningApplication?) {
        guard let name = app?.localizedName, let url = app?.bundleURL, remembered[name] != url.path else { return }
        remembered[name] = url.path
        UserDefaults.standard.set(remembered, forKey: Self.rememberedKey)
    }

    private static let rememberedKey = "appPaths"
    private lazy var remembered = UserDefaults.standard.dictionary(forKey: Self.rememberedKey) as? [String: String] ?? [:]

    func learn(app: String, bundle: String) {
        guard !bundle.isEmpty, bundlesByName[app] != bundle else { return }
        bundlesByName[app] = bundle
        icons[app] = nil
        colors[app] = nil
    }

    func bundleIdentifier(for app: String) -> String? {
        bundlesByName[app] ?? location(of: app).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    private func location(of app: String) -> URL? {
        if let bundle = bundlesByName[app], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { return url }
        if let path = remembered[app], FileManager.default.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        if let url = applicationURLs()[app] { return url }
        NSWorkspace.shared.runningApplications.forEach(remember)
        return remembered[app].map { URL(fileURLWithPath: $0) }
    }

    private func applicationURLs() -> [String: URL] {
        if let urlsByName { return urlsByName }
        var found: [String: URL] = [:]
        let fm = FileManager.default
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities", "/Applications/Utilities",
                     NSHomeDirectory() + "/Applications"]
        for root in roots {
            for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: root).appendingPathComponent(name)
                let display = fm.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                found[display] = found[display] ?? url
                found[(name as NSString).deletingPathExtension] = found[(name as NSString).deletingPathExtension] ?? url
            }
        }
        urlsByName = found
        return found
    }

    private static func averageColor(of image: NSImage) -> Color? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn, pixel[3] > 0 else { return nil }
        let alpha = Double(pixel[3]) / 255
        let ns = NSColor(red: Double(pixel[0]) / 255 / alpha, green: Double(pixel[1]) / 255 / alpha,
                         blue: Double(pixel[2]) / 255 / alpha, alpha: 1)
        return Color(hue: ns.hueComponent, saturation: max(ns.saturationComponent, 0.45), brightness: max(ns.brightnessComponent, 0.7))
    }

    private static func hashColor(_ name: String) -> Color {
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.85)
    }
}
