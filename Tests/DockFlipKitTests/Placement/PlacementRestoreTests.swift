import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("PlacementRestore")
struct PlacementRestoreTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let target = CGRect(x: 100, y: 100, width: 800, height: 600)

    private func ids(_ known: [CGWindowID: PlacementRestore.Known], layout: [CGWindowID: CGRect]? = nil) -> [CGWindowID] {
        PlacementRestore.moves(layout: layout ?? [1: target], screens: [screen], known: known).map(\.id)
    }

    @Test func movesAWindowThatIsElsewhere() {
        let moves = PlacementRestore.moves(
            layout: [1: target], screens: [screen], known: [1: .frame(CGRect(x: 0, y: 0, width: 800, height: 600))]
        )
        #expect(moves.map(\.id) == [1])
        #expect(moves.first?.frame == target)
    }

    @Test func leavesAWindowAlreadyInPlace() {
        // Sub-point differences don't count: the comparison is on whole points.
        #expect(ids([1: .frame(target)]).isEmpty)
        #expect(ids([1: .frame(CGRect(x: 100, y: 100, width: 799.6, height: 600))]).isEmpty)
    }

    @Test func skipsClosedOrMinimizedWindows() {
        #expect(ids([1: .skip]).isEmpty)
        #expect(ids([:]).isEmpty)
    }

    @Test func movesAWindowWhoseFrameWasNeverRead() {
        #expect(ids([1: .unknownFrame]) == [1])
    }

    @Test func skipsAFrameOffEveryConnectedScreen() {
        let offScreen = CGRect(x: 3000, y: 0, width: 800, height: 600)
        #expect(ids([1: .unknownFrame], layout: [1: offScreen]).isEmpty)
    }

    @Test func ordersMovesByWindowID() {
        let layout: [CGWindowID: CGRect] = [9: target, 3: target, 5: target]
        #expect(ids([9: .unknownFrame, 3: .unknownFrame, 5: .unknownFrame], layout: layout) == [3, 5, 9])
    }
}
