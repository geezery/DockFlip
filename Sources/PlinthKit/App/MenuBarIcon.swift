import AppKit

/// Plinth's menu bar symbol: a window standing on a plinth (the taskbar).
/// Drawn in code as a template image, so it follows light/dark menu bars.
enum MenuBarIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()

            // Window outline with a title bar line.
            let window = NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 12, height: 9), xRadius: 2, yRadius: 2)
            window.lineWidth = 1.5
            window.stroke()
            let titleBar = NSBezierPath()
            titleBar.move(to: NSPoint(x: 3.5, y: 5.5))
            titleBar.line(to: NSPoint(x: 14.5, y: 5.5))
            titleBar.lineWidth = 1.2
            titleBar.stroke()

            // The plinth: a solid bar under the window.
            NSBezierPath(roundedRect: NSRect(x: 1, y: 13.5, width: 16, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Plinth"
        return image
    }
}
