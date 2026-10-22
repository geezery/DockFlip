import AppKit

/// DockFlip's menu bar symbol, the app icon in miniature: two windows, the front
/// one overlapping the back one, standing on the Dock with three
/// app slots. Drawn in code as a template image, so it follows light and dark
/// menu bars. Strokes are 1.3 pt with 2.6 pt title bars, so it stays crisp at
/// 18 pt on both 1x and 2x displays.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Back window: outline with a thick title bar.
            fill(NSRect(x: 1.5, y: 1, width: 10, height: 7.5), radius: 1.8)
            clear(NSRect(x: 2.8, y: 3.6, width: 7.4, height: 3.6), radius: 0.5)
            // A gap around the front window, so the two read as separate windows.
            clear(NSRect(x: 4.6, y: 3.1, width: 12.8, height: 9.3), radius: 2.4)
            // Front window.
            fill(NSRect(x: 5.5, y: 4, width: 11, height: 7.5), radius: 1.8)
            clear(NSRect(x: 6.8, y: 6.6, width: 8.4, height: 3.6), radius: 0.5)
            // The Dock, with three app slots.
            fill(NSRect(x: 0.5, y: 13.6, width: 17, height: 3.8), radius: 1.9)
            for x in [4.9, 8.15, 11.4] {
                clear(NSRect(x: x, y: 14.65, width: 1.7, height: 1.7), radius: 0.45)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "DockFlip"
        return image
    }

    private static func fill(_ rect: NSRect, radius: CGFloat) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    /// Punches a transparent hole into what is drawn so far.
    private static func clear(_ rect: NSRect, radius: CGFloat) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        context.compositingOperation = .clear
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        context.restoreGraphicsState()
    }
}
