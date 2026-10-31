/// The Dock icon the mouse rests on whose list had nothing to show when the
/// hover delay ran out. An app's windows are read off the main thread, so an
/// app DockFlip knows no windows of yet (Chrome still building its
/// Accessibility tree, an Office app starting) answers after the list wanted to
/// open: when its windows arrive, the list opens then, without a second hover.
struct WindowListWait: Equatable {
    /// The icon's key, while the mouse is still on it.
    private(set) var key: String?

    /// The hover delay ran out with nothing to list for `key`.
    mutating func nothingToList(_ key: String) {
        self.key = key
    }

    /// The mouse moved to another icon, left the icon, a list opened, or the
    /// icon was pressed (a click that opens a window must not pop a list up under it).
    mutating func stop() {
        key = nil
    }

    /// On a change in the windows: the icon whose list should open now, if any.
    /// An open list keeps itself current; a waiting icon opens once it has windows.
    func keyToOpen(isVisible: Bool, hasWindows: (String) -> Bool) -> String? {
        guard !isVisible, let key, hasWindows(key) else { return nil }
        return key
    }
}
