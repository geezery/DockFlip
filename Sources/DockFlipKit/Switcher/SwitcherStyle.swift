import Foundation

/// How the ⌘Tab switcher looks. The two Alt+Tabs Windows users remember: Flip 3D
/// from Windows 7 and the grid of window pictures from Windows 11. Both behave the
/// same (order, ⌘ release, type to filter); only the drawing differs.
public enum SwitcherStyle: String, Sendable {
    /// Windows 7 Flip 3D: a slanted, receding stack (`SwitcherView`).
    case flip3D
    /// Windows 11 Alt+Tab: rows of window pictures in one panel (`SwitcherGridView`).
    case grid

    /// The style a stored value names, Flip 3D for nothing or an unknown name
    /// (a value from a newer DockFlip, or a typo in an MDM profile).
    public init(stored: String?) {
        self = stored.flatMap(SwitcherStyle.init(rawValue:)) ?? .flip3D
    }
}
