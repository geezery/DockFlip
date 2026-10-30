import Testing
@testable import DockFlipKit

@Suite("SwitcherSelection")
struct SwitcherSelectionTests {
    @Test func startsOnPreviousWindow() {
        #expect(SwitcherSelection(count: 5, reverse: false).index == 1)
        #expect(SwitcherSelection(count: 5, reverse: true).index == 4)
        #expect(SwitcherSelection(count: 1, reverse: false).index == 0)
        #expect(SwitcherSelection(count: 0, reverse: false).index == 0)
    }

    @Test func wrapsAround() {
        var selection = SwitcherSelection(count: 3, reverse: false)
        selection.step(1)
        selection.step(1)
        #expect(selection.index == 0)
        selection.step(-1)
        #expect(selection.index == 2)
    }
}
