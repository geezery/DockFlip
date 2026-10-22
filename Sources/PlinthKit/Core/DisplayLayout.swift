import AppKit

/// Displays, the taskbar's space on each, and the area windows may use.
@MainActor
enum DisplayLayout {
    /// Displays whose taskbar is currently shown (set by TaskbarController).
    static var taskbarDisplays = Set<CGDirectDisplayID>()

    static var primaryHeight: CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return CGDirectDisplayID(number?.uint32Value ?? 0)
    }

    /// Displays ordered left to right (then top to bottom), as Windows orders them for Win+Shift+arrows.
    static func screensLeftToRight() -> [NSScreen] {
        NSScreen.screens.sorted {
            $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.maxY > $1.frame.maxY
        }
    }

    /// Height of the taskbar on `screen`: exactly the space the Dock reserves there,
    /// or 48 pt when the Dock is elsewhere or hidden.
    static func taskbarHeight(for screen: NSScreen) -> CGFloat {
        let dockGap = screen.visibleFrame.minY - screen.frame.minY
        return dockGap >= 36 ? dockGap.rounded() : 48
    }

    /// The area windows may fill on `screen`, in AX space: below the menu bar and
    /// above the taskbar or Dock.
    static func usableArea(of screen: NSScreen) -> CGRect {
        var area = screen.visibleFrame
        if taskbarDisplays.contains(displayID(of: screen)) {
            let bottom = screen.frame.minY + taskbarHeight(for: screen)
            if area.minY < bottom {
                area.size.height -= bottom - area.minY
                area.origin.y = bottom
            }
        }
        return Geometry.axRect(fromCocoa: area, primaryHeight: primaryHeight)
    }

    /// Full frame of `screen` in AX space.
    static func axFrame(of screen: NSScreen) -> CGRect {
        Geometry.axRect(fromCocoa: screen.frame, primaryHeight: primaryHeight)
    }

    /// The screen (from `screens`) that holds most of `frame` (AX space).
    static func screenIndex(for frame: CGRect, in screens: [NSScreen]) -> Int? {
        Geometry.bestScreenIndex(for: frame, screens: screens.map { axFrame(of: $0) })
    }

    static func screen(containingMouse point: NSPoint = NSEvent.mouseLocation) -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
    }
}
