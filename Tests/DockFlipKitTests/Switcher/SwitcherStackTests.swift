import Testing
@testable import DockFlipKit

@Suite("SwitcherStack")
struct SwitcherStackTests {
    @Test func drawsOnlyTheCardsNearTheFrontAmongMany() {
        // Depths 0 through 8 (indices 1...9) and the back card at depth 59 (index 0).
        let drawn = SwitcherStack.drawnIndices(count: 60, selection: 1, visibleDepth: 7)
        #expect(drawn == Array(0...9))
        #expect(drawn.count == 10)
    }

    @Test func wrapsAroundTheEnd() {
        // Front at 57: depths 0...8 are 57, 58, 59, 0...5; the back card is 56.
        let drawn = SwitcherStack.drawnIndices(count: 60, selection: 57, visibleDepth: 7)
        #expect(drawn == [0, 1, 2, 3, 4, 5, 56, 57, 58, 59])
    }

    @Test func drawsEveryCardInASmallStack() {
        #expect(SwitcherStack.drawnIndices(count: 5, selection: 3, visibleDepth: 7) == [0, 1, 2, 3, 4])
        #expect(SwitcherStack.drawnIndices(count: 9, selection: 0, visibleDepth: 7) == Array(0..<9))
        #expect(SwitcherStack.drawnIndices(count: 1, selection: 0, visibleDepth: 7) == [0])
        #expect(SwitcherStack.drawnIndices(count: 0, selection: 0, visibleDepth: 7) == [])
    }

    @Test func aStepInEitherDirectionAnimatesOnlyCardsAlreadyDrawn() {
        // Every card visible before or after a step (depth <= 7) must be drawn on
        // both sides of it, so it moves instead of popping in or out.
        let count = 60
        let visibleDepth = 7
        for selection in [0, 1, 30, 59] {
            let before = Set(SwitcherStack.drawnIndices(count: count, selection: selection, visibleDepth: visibleDepth))
            for delta in [1, -1] {
                let next = ((selection + delta) % count + count) % count
                let after = Set(SwitcherStack.drawnIndices(count: count, selection: next, visibleDepth: visibleDepth))
                for index in 0..<count {
                    let depthBefore = ((index - selection) % count + count) % count
                    let depthAfter = ((index - next) % count + count) % count
                    if depthBefore <= visibleDepth || depthAfter <= visibleDepth {
                        #expect(before.contains(index) && after.contains(index))
                    }
                }
            }
        }
    }

    @Test func toleratesASelectionOutOfRange() {
        #expect(SwitcherStack.drawnIndices(count: 3, selection: 7, visibleDepth: 7) == [0, 1, 2])
        #expect(SwitcherStack.drawnIndices(count: 20, selection: -1, visibleDepth: 1) == [0, 1, 18, 19])
    }
}
