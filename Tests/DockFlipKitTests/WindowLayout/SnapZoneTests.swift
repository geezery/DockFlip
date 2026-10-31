import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapZone")
struct SnapZoneTests {
    // One 1440 x 900 display, Cocoa space.
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    // A second display to the right of it, sharing its right edge.
    let second = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func region(_ x: CGFloat, _ y: CGFloat, _ screens: [CGRect]) -> SnapRegion? {
        SnapZone.zone(at: CGPoint(x: x, y: y), screens: screens)?.region
    }

    @Test func sideEdgesGiveHalves() {
        #expect(region(0, 450, [main]) == .leftHalf)
        #expect(region(3, 450, [main]) == .leftHalf)
        #expect(region(1439, 450, [main]) == .rightHalf)
        #expect(region(1436, 450, [main]) == .rightHalf)
    }

    @Test func topEdgeMaximizes() {
        #expect(region(720, 900, [main]) == .maximized)
        #expect(region(720, 896, [main]) == .maximized)
    }

    @Test func nearACornerGivesQuarters() {
        #expect(region(0, 880, [main]) == .topLeft)
        #expect(region(0, 20, [main]) == .bottomLeft)
        #expect(region(1439, 880, [main]) == .topRight)
        #expect(region(1439, 20, [main]) == .bottomRight)
        #expect(region(40, 900, [main]) == .topLeft)
        #expect(region(1400, 900, [main]) == .topRight)
    }

    @Test func awayFromTheEdgesIsNoZone() {
        #expect(region(720, 450, [main]) == nil)
        #expect(region(5, 450, [main]) == nil)
        #expect(region(720, 0, [main]) == nil)
        #expect(region(-50, 450, [main]) == nil)
    }

    @Test func anEdgeSharedWithAnotherDisplayDoesNotCount() {
        let screens = [main, second]
        #expect(region(1439, 450, screens) == nil)
        #expect(region(1440, 450, screens) == nil)
        // The outer edges still snap, and the zone names the display it is on.
        #expect(region(0, 450, screens) == .leftHalf)
        let right = SnapZone.zone(at: CGPoint(x: 3359, y: 500), screens: screens)
        #expect(right?.region == .rightHalf)
        #expect(right?.screen == 1)
        // The second display is taller: above the first one, its top edge is free.
        #expect(region(1500, 1080, screens) == .topLeft)
    }
}
