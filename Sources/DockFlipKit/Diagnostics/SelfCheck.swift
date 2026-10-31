import Synchronization

/// What DockFlip has seen of the private macOS calls and the Dock hook it rests
/// on. Any of them can stop working in a new macOS with no crash and no error on
/// screen, and DockFlip then just "doesn't work": the debug log's Self-check
/// section names which one, so the bug report comes with its cause.
///
/// The value and its lines are pure, for the tests; `SelfCheck.record` adds what
/// the running app sees, from any thread.
struct SelfCheck: Equatable, Sendable {
    /// How a private call has answered so far.
    struct Calls: Equatable, Sendable {
        var succeeded = 0
        var failed = 0
        /// The error code of the latest failure.
        var lastError: Int32?

        var total: Int { succeeded + failed }

        mutating func record(_ worked: Bool, error: Int32) {
            if worked {
                succeeded += 1
            } else {
                failed += 1
                lastError = error
            }
        }
    }

    /// The searches for windows on other Spaces (`WindowServer.findWindows`).
    struct Walk: Equatable, Sendable {
        var searches = 0
        var sought = 0
        var found = 0
        /// Elements made from a remote token that answered with a window id. None
        /// at all means the tokens no longer reach anything.
        var answered = 0

        mutating func record(sought: Int, found: Int, answered: Int) {
            searches += 1
            self.sought += sought
            self.found += found
            self.answered += answered
        }
    }

    enum DockHook: Equatable, Sendable {
        case notTried
        case attached
        /// Why not, as the log says it.
        case failed(String)
    }

    /// `CGSSetSymbolicHotKeyEnabled`, which turns macOS's own ⌘Tab off.
    var commandTabSwitch = Calls()
    /// `_AXUIElementGetWindow` on the windows apps list, where it should always work.
    var windowIDs = Calls()
    /// `_AXUIElementCreateWithRemoteToken`, which reaches windows on other Spaces.
    var walk = Walk()
    /// The observer on the Dock's icon list, and the hover changes it reported
    /// since it last attached: attached but silent is a Dock that changed.
    var dock = DockHook.notTried
    var dockHovers = 0

    /// The Dock was attached to, again after it restarts (it does when its
    /// settings change), so the count starts over.
    mutating func recordDock(_ hook: DockHook) {
        dock = hook
        dockHovers = 0
    }

    /// The debug log's lines, one per hook: ok, not tried yet, or in capitals what
    /// failed and what the user sees because of it.
    /// - commandTabSwitchFound: `NativeCommandTab.isAvailable`.
    func lines(commandTabSwitchFound: Bool) -> [String] {
        [
            "⌘Tab switch-off, CGSSetSymbolicHotKeyEnabled: " + commandTabSwitchState(found: commandTabSwitchFound),
            "Window ids, _AXUIElementGetWindow: " + windowIDsState,
            "Windows on other Spaces, _AXUIElementCreateWithRemoteToken: " + walkState,
            "Dock hover, AX observer on the Dock: " + dockState
        ]
    }

    private func commandTabSwitchState(found: Bool) -> String {
        guard found else { return "MISSING: macOS's own ⌘Tab stays on" }
        guard commandTabSwitch.total > 0 else { return "found, not used yet" }
        let answers = Self.answers(commandTabSwitch, "call", "calls")
        return commandTabSwitch.succeeded == 0 ? "FAILED, \(answers): macOS's own ⌘Tab stays on" : "ok, \(answers)"
    }

    /// One window that answered is enough: a window closing while it is read
    /// fails too.
    private var windowIDsState: String {
        guard windowIDs.total > 0 else { return "not tried yet: no window read" }
        let answers = Self.answers(windowIDs, "window", "windows")
        return windowIDs.succeeded == 0 ? "FAILED, \(answers): DockFlip sees no windows" : "ok, \(answers)"
    }

    /// Finding none with elements answering can be the time budget running out
    /// in a big app; no element answering at all is the private call failing.
    private var walkState: String {
        guard walk.searches > 0 else { return "not tried yet: no window on another Space or in full screen" }
        let searches = Self.count(walk.searches, "search", "searches")
        let sought = Self.count(walk.sought, "window", "windows")
        if walk.found > 0 { return "ok, \(walk.found) of \(sought) found in \(searches)" }
        if walk.answered == 0 { return "FAILED, no element answered in \(searches): windows on other Spaces and in full screen are missed" }
        return "NONE FOUND, 0 of \(sought) in \(searches)"
    }

    private var dockState: String {
        switch dock {
        case .notTried: return "not tried yet"
        case .failed(let reason): return "FAILED, \(reason): no window list on hover"
        case .attached where dockHovers == 0: return "attached, no hover reported yet: silent if the mouse has rested on a Dock icon"
        case .attached: return "ok, \(Self.count(dockHovers, "hover change", "hover changes")) since attached"
        }
    }

    /// "120 of 122 windows, last error -25202"
    private static func answers(_ calls: Calls, _ one: String, _ many: String) -> String {
        let error = calls.lastError.map { ", last error \($0)" } ?? ""
        return "\(calls.succeeded) of \(count(calls.total, one, many))\(error)"
    }

    private static func count(_ n: Int, _ one: String, _ many: String) -> String {
        n == 1 ? "1 \(one)" : "\(n) \(many)"
    }
}

extension SelfCheck {
    /// What this run has seen. Written from the main thread, from each app's
    /// queue (`WindowsRead`) and from the background searches for windows on
    /// other Spaces, so behind a lock.
    private static let shared = Mutex(SelfCheck())

    /// A copy of what this run has seen, for the debug log.
    static var current: SelfCheck {
        shared.withLock { $0 }
    }

    /// Adds what the app just saw. A lock and no allocation, so the hot paths can
    /// call it on every answer.
    static func record(_ change: (inout SelfCheck) -> Void) {
        shared.withLock { change(&$0) }
    }
}
