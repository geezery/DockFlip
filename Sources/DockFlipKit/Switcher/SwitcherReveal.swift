import Foundation

/// When the ⌘Tab switcher is drawn. Pure, unit-tested.
///
/// ⌘Tab selects and takes the keyboard at once but draws the full-screen stack
/// only after a short hold, as macOS and AltTab do: a quick ⌘Tab or ⌘Tab-Tab
/// switches without the screen flashing.
public enum SwitcherReveal {
    /// How long ⌘ stays held after the first ⌘Tab before the switcher is drawn.
    public static let holdDelay: Duration = .milliseconds(150)

    public enum Action: Equatable {
        /// Draw the switcher.
        case draw
        /// Open the window at this index without drawing anything.
        case open(Int)
        /// Nothing: the switcher has closed already.
        case closed
    }

    /// What to do when the hold is over. ⌘ may have been let go without its
    /// release reaching DockFlip yet (both wait on the main run loop), so the
    /// live ⌘ state decides: up means switch, as a release would.
    public static func afterHold(selection: SwitcherSelection?, query: String, commandHeld: Bool) -> Action {
        guard selection != nil else { return .closed }
        if let index = SwitcherRelease.windowToOpen(selection: selection, query: query, commandHeld: commandHeld) {
            return .open(index)
        }
        return .draw
    }

    /// Typing a filter draws the switcher at once, without waiting for the
    /// hold: a filter is only any use when you see what it leaves.
    public static func drawsAtOnce(query: String) -> Bool {
        !query.isEmpty
    }
}
