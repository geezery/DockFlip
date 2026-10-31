import Testing
@testable import DockFlipKit

@Suite("Clean Up refresh")
struct CleanupRefreshTests {
    /// An app quit from the Dock while Clean Up is open: one look, after the wait.
    @Test func changeWhileOpenLooksAgain() {
        var refresh = CleanupRefresh()
        #expect(refresh.changed(isVisible: true))
        #expect(refresh.fire(isVisible: true))
        #expect(!refresh.isPending)
    }

    /// A quitting app closes many windows at once: they make one look, not many.
    @Test func burstOfChangesMakesOneLook() {
        var refresh = CleanupRefresh()
        #expect(refresh.changed(isVisible: true))
        #expect(!refresh.changed(isVisible: true))
        #expect(!refresh.changed(isVisible: true))
        #expect(refresh.fire(isVisible: true))
        #expect(refresh.changed(isVisible: true))
    }

    /// A closed Clean Up does no work; `show()` looks again when it opens.
    @Test func changeWhileClosedDoesNothing() {
        var refresh = CleanupRefresh()
        #expect(!refresh.changed(isVisible: false))
        #expect(!refresh.isPending)
    }

    /// Closed during the wait: no look.
    @Test func closedDuringTheWaitSkipsTheLook() {
        var refresh = CleanupRefresh()
        #expect(refresh.changed(isVisible: true))
        #expect(!refresh.fire(isVisible: false))
        #expect(!refresh.isPending)
    }
}
