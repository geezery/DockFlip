import CoreGraphics

/// What a click on a Dock icon does, decided from what DockFlip already knows.
/// Pure, unit-tested.
///
/// Every left click on the Mac waits for the Dock click tap, so the tap only
/// reads memory: the icon the Dock highlighted (from hover) and the registry's
/// windows. The click's work (`action`) runs after the tap has answered.
enum DockClick {
    /// A window of the clicked app, as the click rule needs it.
    struct Window: Equatable {
        let id: CGWindowID
        let isMinimized: Bool
    }

    enum Action: Equatable {
        /// Bring back the window the previous click on this icon minimized.
        case restore(CGWindowID)
        /// The app's active window is in front: minimize it.
        case minimize(CGWindowID)
        /// Bring the app's most recent window forward.
        case focus(CGWindowID)
        /// The app has no windows after all: the click is the Dock's (launch, reopen).
        case handToDock
    }

    /// The app of the icon the Dock highlighted, when `point` (AX coordinates)
    /// is on that icon's frame. Nil means the tap must ask the Dock: no icon was
    /// highlighted yet, or the frame read at hover time has moved since (the
    /// Dock's magnification), and a stale guess would act on the wrong app.
    static func hoveredBundleID(_ hovered: (bundleID: String, frame: CGRect)?, at point: CGPoint) -> String? {
        guard let hovered, hovered.frame.contains(point) else { return nil }
        return hovered.bundleID
    }

    /// The Windows taskbar click: the front app's active window minimizes, and
    /// the next click on the same icon brings that same window back; otherwise
    /// the app's most recent window comes forward (restored if minimized).
    /// - windows: the app's windows, most recently used first.
    /// - active: the most recent window of the frontmost app, if any.
    static func action(
        windows: [Window],
        bundleID: String,
        active: CGWindowID?,
        minimizedByClick: (bundleID: String, windowID: CGWindowID)?
    ) -> Action {
        if let last = minimizedByClick, last.bundleID == bundleID,
           windows.contains(where: { $0.id == last.windowID && $0.isMinimized }) {
            return .restore(last.windowID)
        }
        if let active, windows.contains(where: { $0.id == active }) {
            return .minimize(active)
        }
        if let first = windows.first {
            return .focus(first.id)
        }
        return .handToDock
    }
}
