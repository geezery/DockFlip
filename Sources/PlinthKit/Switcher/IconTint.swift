import AppKit
import SwiftUI

/// An app's characteristic colour, taken from its icon (the average of its
/// opaque pixels, pushed towards a usable saturation). Cached per app.
@MainActor
enum IconTint {
    private static var cache: [String: Color] = [:]

    static func color(for icon: NSImage?, key: String) -> Color {
        if let cached = cache[key] { return cached }
        let color = icon.flatMap(average(of:)) ?? Color.accentColor
        cache[key] = color
        return color
    }

    private static func average(of image: NSImage) -> Color? {
        let size = 16
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard drawn else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 200 {
            red += Double(pixels[i]); green += Double(pixels[i + 1]); blue += Double(pixels[i + 2])
            count += 1
        }
        guard count > 0 else { return nil }
        let base = NSColor(srgbRed: red / count / 255, green: green / count / 255, blue: blue / count / 255, alpha: 1)
        // Washed-out icons would give grey title bars; keep some colour.
        let tuned = NSColor(
            hue: base.hueComponent,
            saturation: max(base.saturationComponent, 0.45),
            brightness: min(max(base.brightnessComponent, 0.55), 0.9),
            alpha: 1
        )
        return Color(nsColor: tuned)
    }
}
