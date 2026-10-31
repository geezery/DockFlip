import CoreGraphics

/// Windows 11 Snap Assist rules, pure and unit-tested: after a window snaps, which
/// region is left to fill and which windows to offer for it. No UI here yet.
public enum SnapAssist {
    /// The region left beside a window just snapped to `snapped`: the other half,
    /// or for a quarter the rest of its own half. A maximized window leaves nothing.
    public static func remainingRegion(after snapped: SnapRegion) -> SnapRegion? {
        switch snapped {
        case .leftHalf: return .rightHalf
        case .rightHalf: return .leftHalf
        case .topLeft: return .bottomLeft
        case .bottomLeft: return .topLeft
        case .topRight: return .bottomRight
        case .bottomRight: return .topRight
        case .maximized: return nil
        }
    }

    /// The windows to offer for the region left, in the order given (most recently
    /// used first). Like Windows, minimized windows and hidden apps' windows are
    /// offered; the snapped window itself, windows on other Spaces and windows with
    /// no size (a failed read; minimized ones may legitimately have none) are not.
    public static func candidates(from windows: [WindowSnapshot], excluding snappedID: CGWindowID) -> [WindowSnapshot] {
        windows.filter { window in
            window.id != snappedID
                && !window.isOnOtherSpace
                && (window.isMinimized || (window.frame.width > 0 && window.frame.height > 0))
        }
    }
}
