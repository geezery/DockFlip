import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("Clean Up selection")
struct CleanupSelectionTests {
    typealias Target = CleanupRow.Target

    let a = Target.window(1)
    let b = Target.window(2)
    let c = Target.app(300)

    /// The first look ticks every suggestion.
    @Test func firstLookTicksEveryRow() {
        let selected = CleanupSelection.afterReload(listed: [a, b, c], previouslyListed: [], selected: [])
        #expect(selected == [a, b, c])
    }

    /// Three suggestions, one unticked, the other two closed: the row the user kept
    /// is still unticked after the reload, so the next Close Selected leaves it alone.
    @Test func closeSelectedKeepsTheUntickedRowUnticked() {
        let selected = CleanupSelection.afterReload(listed: [a], previouslyListed: [a, b, c], selected: [b, c])
        #expect(selected.isEmpty)
    }

    /// Keep on one row: the unticked row stays unticked, the ticked one stays ticked.
    @Test func keepLeavesTheOtherRowsAsTheyWere() {
        let selected = CleanupSelection.afterReload(listed: [a, c], previouslyListed: [a, b, c], selected: [b, c])
        #expect(selected == [c])
    }

    /// A row that is new since the last look comes in ticked; rows gone from the
    /// list drop out of the selection.
    @Test func newRowsAreTickedAndGoneRowsDropOut() {
        let selected = CleanupSelection.afterReload(listed: [a, c], previouslyListed: [a, b], selected: [b])
        #expect(selected == [c])
    }
}
