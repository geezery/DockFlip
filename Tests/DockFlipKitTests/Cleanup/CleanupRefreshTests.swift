import Testing
@testable import DockFlipKit

/// `#expect` cannot call a mutating method: each answer goes into a `let` first.
@Suite("Clean Up refresh")
struct CleanupRefreshTests {
    /// An app quit from the Dock while Clean Up is open: one look, after the wait.
    @Test func changeWhileOpenLooksAgain() {
        var refresh = CleanupRefresh()
        let waits = refresh.changed(isVisible: true)
        let looks = refresh.fire(isVisible: true)
        #expect(waits)
        #expect(looks)
        #expect(!refresh.isPending)
    }

    /// A quitting app closes many windows at once: they make one look, not many.
    @Test func burstOfChangesMakesOneLook() {
        var refresh = CleanupRefresh()
        let first = refresh.changed(isVisible: true)
        let second = refresh.changed(isVisible: true)
        let third = refresh.changed(isVisible: true)
        let looks = refresh.fire(isVisible: true)
        let afterLook = refresh.changed(isVisible: true)
        #expect(first)
        #expect(!second)
        #expect(!third)
        #expect(looks)
        #expect(afterLook)
    }

    /// A closed Clean Up does no work; `show()` looks again when it opens.
    @Test func changeWhileClosedDoesNothing() {
        var refresh = CleanupRefresh()
        let waits = refresh.changed(isVisible: false)
        #expect(!waits)
        #expect(!refresh.isPending)
    }

    /// Closed during the wait: no look.
    @Test func closedDuringTheWaitSkipsTheLook() {
        var refresh = CleanupRefresh()
        let waits = refresh.changed(isVisible: true)
        let looks = refresh.fire(isVisible: false)
        #expect(waits)
        #expect(!looks)
        #expect(!refresh.isPending)
    }
}
