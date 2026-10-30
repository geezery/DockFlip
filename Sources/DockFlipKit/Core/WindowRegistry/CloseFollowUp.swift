/// What DockFlip does a moment after it pressed a window's close button.
///
/// An app that asks to save attaches its sheet to that window — which may be
/// minimized, behind other windows or on another desktop. There the question is
/// invisible and × seems to do nothing. Windows brings the question forward, so
/// DockFlip focuses the window when it is still there and asking.
enum CloseFollowUp: Equatable {
    /// The window closed, or it is visible and closing in its own time.
    case done
    /// The window is still there and waiting for an answer: bring it forward.
    case bringForward
    /// The app did not answer the read: ask once more a little later.
    case lookAgain

    /// What DockFlip read of the window after pressing close.
    struct Check: Equatable {
        /// Its element is no longer valid, or Accessibility said it was destroyed.
        var isGone: Bool
        /// False when the app was busy and the read timed out.
        var answered: Bool
        var hasSheet: Bool
        var isMinimized: Bool
    }

    /// `isLastLook`: this was the second look; a busy app is not asked again.
    static func after(_ check: Check, isLastLook: Bool) -> CloseFollowUp {
        if check.isGone { return .done }
        // A failed read is not an answer: neither "closed" nor "asking".
        if !check.answered { return isLastLook ? .done : .lookAgain }
        if check.hasSheet { return .bringForward }
        // Some apps hold the sheet back until a minimized window is back on screen,
        // and a minimized window that is still there did not close.
        if check.isMinimized { return .bringForward }
        // A visible window without a sheet is closing slowly, or hides itself
        // instead of closing: pulling it forward would only get in the way.
        return .done
    }
}
