import CoreGraphics

/// Coordinate helpers. Accessibility and CGWindowList use global coordinates with
/// the origin at the top-left of the primary display ("AX space"); AppKit's NSScreen
/// uses the bottom-left ("Cocoa space").
public enum Geometry {
    public static func axRect(fromCocoa rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func cocoaRect(fromAX rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the screen that holds most of `window`, or nil if none intersects.
    public static func bestScreenIndex(for window: CGRect, screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = window.intersection(screen)
            guard !overlap.isNull, !overlap.isEmpty else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }

    /// `window` expressed as fractions (0…1) of `screen`, clamped to the screen.
    public static func normalized(_ window: CGRect, in screen: CGRect) -> CGRect {
        guard screen.width > 0, screen.height > 0 else { return .zero }
        let clipped = window.intersection(screen)
        let rect = clipped.isNull ? window : clipped
        return CGRect(
            x: (rect.minX - screen.minX) / screen.width,
            y: (rect.minY - screen.minY) / screen.height,
            width: rect.width / screen.width,
            height: rect.height / screen.height
        )
    }
}
