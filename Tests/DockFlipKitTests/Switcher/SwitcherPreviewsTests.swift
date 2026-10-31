import Testing
@testable import DockFlipKit

@Suite("SwitcherPreviews")
struct SwitcherPreviewsTests {
    /// Window ids 100, 101, … so they never pass for indices.
    private func ids(_ count: Int) -> [Int] { (0..<count).map { 100 + $0 } }

    private func capture(_ ids: [Int], selection: Int, asked: Set<Int> = [], lookAhead: Bool) -> [Int] {
        SwitcherPreviews.toCapture(ids: ids, selection: selection, visibleDepth: SwitcherStack.visibleDepth,
                                   asked: asked, lookAhead: lookAhead)
    }

    @Test func openingAsksForTheSixteenNearestTheFrontFrontFirst() {
        // Depths 0...8 (indices 1...9), the back card (index 0), then depths 9...14.
        let asked = capture(ids(30), selection: 1, lookAhead: true)
        #expect(asked == [101, 102, 103, 104, 105, 106, 107, 108, 109, 100, 110, 111, 112, 113, 114, 115])
        #expect(asked.count == SwitcherPreviews.batch)
    }

    @Test func openingBackwardsAsksForTheFrontCardAtTheEnd() {
        // ⌘⇧Tab opens on the last window; the first sixteen alone would miss it.
        let asked = capture(ids(30), selection: 29, lookAhead: true)
        #expect(asked.first == 129)
        #expect(asked.contains(128)) // the back card, in front after one more ⇧ step
        #expect(asked.count == SwitcherPreviews.batch)
    }

    @Test func steppingToTheTwentiethWindowAsksForItWhileItComesIntoSight() {
        let windows = ids(30)
        var asked = Set(capture(windows, selection: 1, lookAhead: true))
        var askedAt = [[Int]](repeating: [], count: 20)
        for selection in 2...19 {
            let new = capture(windows, selection: selection, asked: asked, lookAhead: false)
            #expect(new.count <= 1) // one card comes into sight per step
            askedAt[selection] = new
            asked.formUnion(new)
        }
        // Nothing new until depth 8 reaches index 16; the 20th window (index 19)
        // is asked for at selection 11, eight steps before it is in front.
        #expect(askedAt[7] == [])
        #expect(askedAt[8] == [116])
        #expect(askedAt[11] == [119])
        #expect(askedAt[19] == [127])
        #expect(asked.contains(119))
    }

    @Test func steppingBackAsksForTheCardsComingFromTheBack() {
        let windows = ids(30)
        let asked = Set(capture(windows, selection: 1, lookAhead: true))
        // At selection 0 the back card is index 29; at 29 it is index 28.
        #expect(capture(windows, selection: 0, asked: asked, lookAhead: false) == [129])
        #expect(capture(windows, selection: 29, asked: asked.union([129]), lookAhead: false) == [128])
    }

    @Test func aStepAsksOnlyForDrawnCardsNotYetAsked() {
        // Only two of the drawn cards asked for so far: a step asks for the other
        // drawn cards, front first and the back card last, never the ones behind them.
        let new = capture(ids(30), selection: 10, asked: [110, 111], lookAhead: false)
        #expect(new == [112, 113, 114, 115, 116, 117, 118, 109])
    }

    @Test func neverStartsMoreThanOneBatch() {
        #expect(capture(ids(60), selection: 0, lookAhead: true).count == SwitcherPreviews.batch)
        let deep = SwitcherPreviews.toCapture(ids: ids(60), selection: 0, visibleDepth: 30, asked: [], lookAhead: false)
        #expect(deep.count == SwitcherPreviews.batch)
    }

    @Test func aSmallStackIsAskedForWholeAtOnce() {
        let windows = ids(5)
        let asked = capture(windows, selection: 1, lookAhead: true)
        #expect(Set(asked) == Set(windows))
        #expect(capture(windows, selection: 2, asked: Set(asked), lookAhead: false) == [])
        #expect(capture([], selection: 0, lookAhead: true) == [])
    }

    @Test func toleratesASelectionOutOfRange() {
        #expect(capture(ids(3), selection: 7, lookAhead: false) == [101, 102, 100])
        #expect(capture(ids(3), selection: -1, lookAhead: false) == [102, 100, 101])
    }

    // MARK: - The Windows 11 grid (`toCaptureAround`)

    @Test func gridAsksForTheWindowsAroundTheSelectionNearestFirst() {
        let asked = SwitcherPreviews.toCaptureAround(ids: ids(10), selection: 1, asked: [], limit: 5)
        // Not 109: the last window sits in the grid's last row, out of sight.
        #expect(asked == [101, 102, 100, 103, 104])
    }

    @Test func gridAsksForEveryWindowOnceAndOnlyNewOnes() {
        let windows = ids(5)
        let all = SwitcherPreviews.toCaptureAround(ids: windows, selection: 4, asked: [], limit: 24)
        #expect(Set(all) == Set(windows))
        #expect(all.count == windows.count)
        #expect(all.first == 104) // ⌘⇧Tab opens on the last window: it comes first
        let again = SwitcherPreviews.toCaptureAround(ids: windows, selection: 2, asked: Set(all), limit: 24)
        #expect(again.isEmpty)
        #expect(SwitcherPreviews.toCaptureAround(ids: ids(0), selection: 0, asked: [], limit: 24).isEmpty)
    }
}
