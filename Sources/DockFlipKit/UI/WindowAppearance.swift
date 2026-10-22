import AppKit
import SwiftUI

/// How a window is drawn when there is no picture of it: where it sits on its
/// display (for `Minimap`) and its app's colour (for tinted title bars).
/// Shared by the ⌘Tab switcher and the Dock window list.
@MainActor
enum WindowAppearance {
    /// The window's outline as fractions (0…1) of its display, and that display.
    static func placement(of frame: CGRect) -> (minimap: CGRect, screen: NSScreen)? {
        let screens = NSScreen.screens
        guard let index = DisplayLayout.screenIndex(for: frame, in: screens) else { return nil }
        return (Geometry.normalized(frame, in: DisplayLayout.axFrame(of: screens[index])), screens[index])
    }

    /// The app's characteristic colour.
    static func tint(of window: WindowSnapshot) -> Color {
        let key = window.bundleID ?? window.appName
        if let cached = tints[key] { return cached }
        let color = window.icon.flatMap(averageColor(of:)) ?? Color.accentColor
        tints[key] = color
        return color
    }

    private static var tints: [String: Color] = [:]

    /// The average of the icon's opaque pixels, pushed towards a usable saturation.
    private static func averageColor(of image: NSImage) -> Color? {
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
