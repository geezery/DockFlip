import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("DockAim")
struct DockAimTests {
    // A bottom Dock: icons 64 pt wide at y 0…64, the list open above the icon at x 600…664.
    private let list = CGRect(x: 482, y: 90, width: 300, height: 200)

    // MARK: - Heading for the list

    @Test func diagonalOverTheRightNeighbourHeadsForTheList() {
        // From the list's icon up and right, over the next icon, towards the list's right end.
        #expect(DockAim.isHeading(from: CGPoint(x: 650, y: 40), to: CGPoint(x: 670, y: 50), list: list, edge: .bottom))
    }

    @Test func diagonalOverTheLeftNeighbourHeadsForTheList() {
        #expect(DockAim.isHeading(from: CGPoint(x: 610, y: 40), to: CGPoint(x: 590, y: 50), list: list, edge: .bottom))
    }

    @Test func slidingAlongTheDockIsAMoveToTheNextIcon() {
        #expect(!DockAim.isHeading(from: CGPoint(x: 650, y: 40), to: CGPoint(x: 680, y: 40), list: list, edge: .bottom))
        // A slight rise while sliding sideways still misses the list.
        #expect(!DockAim.isHeading(from: CGPoint(x: 650, y: 40), to: CGPoint(x: 690, y: 42), list: list, edge: .bottom))
    }

    @Test func movingAwayFromTheListIsNotAiming() {
        #expect(!DockAim.isHeading(from: CGPoint(x: 650, y: 40), to: CGPoint(x: 670, y: 30), list: list, edge: .bottom))
    }

    @Test func passingTheListsEndIsNotAiming() {
        // Up, but so far sideways that the line passes beside the list.
        #expect(!DockAim.isHeading(from: CGPoint(x: 650, y: 80), to: CGPoint(x: 800, y: 85), list: list, edge: .bottom))
    }

    @Test func notMovingIsNotAiming() {
        let here = CGPoint(x: 650, y: 40)
        #expect(!DockAim.isHeading(from: here, to: here, list: list, edge: .bottom))
    }

    @Test func sideDocksAimSideways() {
        // A left Dock: the list opens to the right of the icon.
        let right = CGRect(x: 90, y: 400, width: 300, height: 200)
        #expect(DockAim.isHeading(from: CGPoint(x: 40, y: 500), to: CGPoint(x: 50, y: 480), list: right, edge: .left))
        #expect(!DockAim.isHeading(from: CGPoint(x: 40, y: 500), to: CGPoint(x: 40, y: 470), list: right, edge: .left))
        // A right Dock (screen 1440 wide): the list opens to the left.
        let left = CGRect(x: 1050, y: 400, width: 300, height: 200)
        #expect(DockAim.isHeading(from: CGPoint(x: 1400, y: 500), to: CGPoint(x: 1390, y: 515), list: left, edge: .right))
    }

    @Test func distanceShrinksTowardsTheList() {
        #expect(DockAim.distance(from: CGPoint(x: 650, y: 40), to: list, edge: .bottom) == 50)
        #expect(DockAim.distance(from: CGPoint(x: 650, y: 60), to: list, edge: .bottom) == 30)
    }

    // MARK: - The trail

    @Test func originIsTheOldestOtherPosition() {
        var aim = DockAim()
        #expect(aim.origin(before: CGPoint(x: 1, y: 1)) == nil)
        for x in 1...6 { aim.moved(to: CGPoint(x: CGFloat(x), y: 0)) }
        // Only the last few positions are kept.
        #expect(aim.trail.count == DockAim.trailLength)
        #expect(aim.origin(before: CGPoint(x: 6, y: 0)) == CGPoint(x: 3, y: 0))
    }

    @Test func repeatedPositionsKeepTheDirection() {
        var aim = DockAim()
        aim.moved(to: CGPoint(x: 1, y: 0))
        aim.moved(to: CGPoint(x: 2, y: 0))
        aim.moved(to: CGPoint(x: 2, y: 0))
        #expect(aim.trail == [CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0)])
        #expect(aim.origin(before: CGPoint(x: 2, y: 0)) == CGPoint(x: 1, y: 0))
    }
}
