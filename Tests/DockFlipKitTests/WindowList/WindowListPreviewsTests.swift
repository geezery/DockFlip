import CoreGraphics
import SwiftUI
import Testing
@testable import DockFlipKit

/// The list opens with pictures of its first eight windows; a later window
/// gets its picture when the mouse reaches it, so the peek pane is never empty.
@Suite("WindowListPreviews: the first batch and the hovered window")
@MainActor
struct WindowListPreviewsTests {
    let twelve = (1...12).map { CGWindowID($0) }

    @Test func listOpensWithTheFirstEight() {
        #expect(WindowListPreviews.firstBatch(twelve) == Array(twelve.prefix(8)))
        #expect(WindowListPreviews.firstBatch([3, 4]) == [3, 4])
    }

    @Test func eleventhWindowIsCapturedOnHover() {
        let first = Set(WindowListPreviews.firstBatch(twelve))
        #expect(WindowListPreviews.onHover(11, listed: twelve, requested: first, shown: []) == 11)
    }

    @Test func nothingIsCapturedTwice() {
        let first = Set(WindowListPreviews.firstBatch(twelve))
        // In the first batch, already captured on an earlier hover, or pictured.
        #expect(WindowListPreviews.onHover(3, listed: twelve, requested: first, shown: []) == nil)
        #expect(WindowListPreviews.onHover(11, listed: twelve, requested: first.union([11]), shown: []) == nil)
        #expect(WindowListPreviews.onHover(11, listed: twelve, requested: first, shown: [11]) == nil)
        // Not this list's window, or nothing hovered.
        #expect(WindowListPreviews.onHover(99, listed: twelve, requested: first, shown: []) == nil)
        #expect(WindowListPreviews.onHover(nil, listed: twelve, requested: first, shown: []) == nil)
    }

    @Test func hoveringARowOrTabTellsThePopupOnce() {
        let model = WindowListModel()
        var told: [CGWindowID] = []
        model.peekChanged = { told.append($0) }
        model.setHovered(11, true)
        model.setHovered(11, false)
        model.setHovered(11, true)   // the same window again: already asked
        model.setHoveredTab("t", window: 12, true)
        #expect(told == [11, 12])
        // A new list forgets the peek, so the same window asks again there.
        model.startNewList()
        model.setHovered(11, true)
        #expect(told == [11, 12, 11])
    }
}
