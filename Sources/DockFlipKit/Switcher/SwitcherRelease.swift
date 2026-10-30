import Foundation

/// When letting go of ⌘ opens the selected window. Pure, unit-tested.
public enum SwitcherRelease {
    /// The window to open, or nil to keep switching: ⌘ is up, the switcher is
    /// open and nothing is typed (while filtering, Return opens the window).
    ///
    /// The switcher asks this when ⌘ is released, and once more as it opens: a
    /// quick ⌘Tab can let go of ⌘ before the hot key is handled, and then no
    /// release follows (AltTab checks the same way).
    public static func windowToOpen(selection: SwitcherSelection?, query: String, commandHeld: Bool) -> Int? {
        guard let selection, query.isEmpty, !commandHeld else { return nil }
        return selection.index
    }
}
