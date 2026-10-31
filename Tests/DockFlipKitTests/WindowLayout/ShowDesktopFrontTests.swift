import Testing
@testable import DockFlipKit

@Suite("Show Desktop: the window given back")
struct ShowDesktopFrontTests {
    /// Typing in TextEdit, ⌃⌥D twice: TextEdit's window gets the keyboard back.
    @Test func theFrontWindowComesBack() {
        let front = ShowDesktopFront(pid: 42, windowID: 7)
        let restored = ShowDesktopFront.toRestore(front, unhidden: [10, 42, 99])
        #expect(restored == front)
    }

    /// An app with no window DockFlip knows is still brought forward.
    @Test func anAppWithoutAKnownWindowComesBackToo() {
        let front = ShowDesktopFront(pid: 42, windowID: nil)
        let restored = ShowDesktopFront.toRestore(front, unhidden: [42])
        #expect(restored == front)
    }

    /// The front app was brought back by hand (or quit): leave the keyboard where it is.
    @Test func anAppNoLongerHiddenIsLeftAlone() {
        let front = ShowDesktopFront(pid: 42, windowID: 7)
        let restored = ShowDesktopFront.toRestore(front, unhidden: [10, 99])
        #expect(restored == nil)
    }

    @Test func nothingInFrontRestoresNothing() {
        let restored = ShowDesktopFront.toRestore(nil, unhidden: [10])
        #expect(restored == nil)
    }
}
