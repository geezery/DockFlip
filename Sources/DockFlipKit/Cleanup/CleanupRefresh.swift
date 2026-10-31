/// When an open Clean Up window looks again, so a window closed elsewhere or an
/// app quit from the Dock leaves the list without reopening it.
///
/// Changes come in bursts (an app that quits closes all its windows, a drag moves
/// one many times), so they are gathered into one look after a short one-shot wait.
/// A hidden window ignores them: `show()` looks again anyway.
struct CleanupRefresh {
    /// The one-shot wait between the first change and the look.
    static let delay: Duration = .milliseconds(300)

    private(set) var isPending = false

    /// A change came in. True: start the one-shot wait now.
    mutating func changed(isVisible: Bool) -> Bool {
        guard isVisible, !isPending else { return false }
        isPending = true
        return true
    }

    /// The wait is over. True: look again, the window is still on screen.
    mutating func fire(isVisible: Bool) -> Bool {
        isPending = false
        return isVisible
    }
}
