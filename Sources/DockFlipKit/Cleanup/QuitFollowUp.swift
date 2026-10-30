/// What Clean Up does a moment after it asked an app to quit.
///
/// An app with unsaved documents answers a quit request with a "review changes"
/// question — in its own windows, which stay invisible while the app is hidden
/// or behind Clean Up. Then the app seems not to quit. Windows brings that
/// question forward, so DockFlip shows the app when it is still running.
enum QuitFollowUp: Equatable {
    /// The app quit, was never asked, or is already in front.
    case done
    /// The app is still running after the request: unhide and activate it.
    case bringForward

    /// What DockFlip read of the app a moment after `terminate()`.
    struct Check: Equatable {
        /// `terminate()` returned true: the request reached the app.
        var wasAsked: Bool
        var isTerminated: Bool
        var isHidden: Bool
        var isActive: Bool
    }

    static func after(_ check: Check) -> QuitFollowUp {
        // A request that never reached the app leaves nothing to answer.
        guard check.wasAsked, !check.isTerminated else { return .done }
        // Already in front and visible: its question is on screen.
        if check.isActive && !check.isHidden { return .done }
        return .bringForward
    }
}
