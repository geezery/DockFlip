import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("DockClick")
struct DockClickTests {
    private let safari = "com.apple.Safari"
    private let icon = CGRect(x: 600, y: 1380, width: 64, height: 64)

    // MARK: - Which icon, from memory

    @Test func pressOnTheHighlightedIconNeedsNoCallToTheDock() {
        let hovered = (bundleID: safari, frame: icon)
        #expect(DockClick.hoveredBundleID(hovered, at: CGPoint(x: 630, y: 1410)) == safari)
    }

    @Test func pressOffTheHighlightedIconAsksTheDock() {
        // Magnification moved the icons since the hover, or the press is on a neighbour.
        let hovered = (bundleID: safari, frame: icon)
        #expect(DockClick.hoveredBundleID(hovered, at: CGPoint(x: 680, y: 1410)) == nil)
    }

    @Test func pressWithNoHighlightedIconAsksTheDock() {
        #expect(DockClick.hoveredBundleID(nil, at: CGPoint(x: 630, y: 1410)) == nil)
    }

    // MARK: - What the click does

    private func window(_ id: CGWindowID, minimized: Bool = false) -> DockClick.Window {
        DockClick.Window(id: id, isMinimized: minimized)
    }

    @Test func clickOnTheFrontAppMinimizesItsActiveWindow() {
        let action = DockClick.action(windows: [window(1), window(2)], bundleID: safari, active: 1, minimizedByClick: nil)
        #expect(action == .minimize(1))
    }

    @Test func nextClickBringsTheMinimizedWindowBack() {
        // Safari's most recent window is another one now; the click restores the one it minimized.
        let action = DockClick.action(
            windows: [window(2, minimized: true), window(1, minimized: true)],
            bundleID: safari, active: nil, minimizedByClick: (safari, 1)
        )
        #expect(action == .restore(1))
    }

    @Test func clickOnAnotherAppBringsItsMostRecentWindowForward() {
        let action = DockClick.action(windows: [window(5), window(6)], bundleID: safari, active: 9, minimizedByClick: nil)
        #expect(action == .focus(5))
    }

    @Test func aWindowMinimizedFromAnotherIconIsNotRestoredHere() {
        let action = DockClick.action(
            windows: [window(5), window(6, minimized: true)],
            bundleID: safari, active: nil, minimizedByClick: ("com.apple.mail", 6)
        )
        #expect(action == .focus(5))
    }

    @Test func aWindowRestoredSinceIsNotRestoredAgain() {
        // The user brought it back another way: it is the front window, so the click minimizes it.
        let action = DockClick.action(windows: [window(1)], bundleID: safari, active: 1, minimizedByClick: (safari, 1))
        #expect(action == .minimize(1))
    }

    @Test func appWhoseWindowsAreGoneLeavesTheClickToTheDock() {
        // The tap held the press back from memory; the window list says it has none after all.
        let action = DockClick.action(windows: [], bundleID: safari, active: nil, minimizedByClick: (safari, 1))
        #expect(action == .handToDock)
    }
}
