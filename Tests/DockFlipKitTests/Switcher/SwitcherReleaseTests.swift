import Testing
@testable import DockFlipKit

@Suite("SwitcherRelease")
struct SwitcherReleaseTests {
    @Test func quickFlickOpensPreviousWindow() {
        // ⌘ was already up when the switcher opened: switch to the previous window.
        let opened = SwitcherSelection(count: 3, reverse: false)
        #expect(SwitcherRelease.windowToOpen(selection: opened, query: "", commandHeld: false) == 1)
        let reversed = SwitcherSelection(count: 3, reverse: true)
        #expect(SwitcherRelease.windowToOpen(selection: reversed, query: "", commandHeld: false) == 2)
    }

    @Test func staysOpenWhileCommandIsHeld() {
        let opened = SwitcherSelection(count: 3, reverse: false)
        #expect(SwitcherRelease.windowToOpen(selection: opened, query: "", commandHeld: true) == nil)
    }

    @Test func filteringWaitsForReturn() {
        let opened = SwitcherSelection(count: 3, reverse: false)
        #expect(SwitcherRelease.windowToOpen(selection: opened, query: "team", commandHeld: false) == nil)
    }

    @Test func closedSwitcherOpensNothing() {
        // A late ⌘ release after the switcher already switched.
        #expect(SwitcherRelease.windowToOpen(selection: nil, query: "", commandHeld: false) == nil)
    }
}
