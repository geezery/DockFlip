import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapLayoutBar")
struct SnapLayoutBarTests {
    // A 1440 x 900 display with a 33 pt menu bar and the Dock below, Cocoa space.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let visible = CGRect(x: 0, y: 70, width: 1440, height: 797)

    var bar: CGRect { SnapLayoutBar.frame(visible: visible, count: SnapLayouts.all.count) }

    /// A drag that starts mid-screen and ends at `mouse`.
    func tracked(to mouse: CGPoint, from start: CGPoint = CGPoint(x: 720, y: 450),
                 screens: [CGRect]? = nil, visibles: [CGRect]? = nil) -> Int? {
        var tracking = SnapLayoutBar()
        tracking.track(mouse: mouse, start: start, screens: screens ?? [screen], visibles: visibles ?? [visible])
        return tracking.screen
    }

    @Test func theBarSitsCentredUnderTheMenuBar() {
        #expect(bar.midX == 720)
        #expect(bar.maxY == visible.maxY - SnapLayoutBar.topGap)
        #expect(bar.size == SnapLayoutBar.size(count: SnapLayouts.all.count))
    }

    @Test func suggestionsComeFirstWhenThereAreWindowsToSuggest() {
        #expect(SnapLayoutBar.tiles(others: []).count == SnapLayouts.all.count)
        #expect(SnapLayoutBar.tiles(others: []).allSatisfy { $0.filled.isEmpty && $0.openZone == nil })

        let one = SnapLayoutBar.tiles(others: [7])
        #expect(one.count == SnapLayouts.all.count + 1)
        #expect(one[0].layout == SnapLayouts.all[0])
        #expect(one[0].filled == [1: 7])
        #expect(one[0].openZone == 0)

        let two = SnapLayoutBar.tiles(others: [7, 9])
        #expect(two.count == SnapLayouts.all.count + 2)
        #expect(two[1].layout == SnapLayouts.all[2])
        #expect(two[1].filled == [1: 7, 2: 9])
        #expect(two[1].openZone == 0)
        #expect(Array(two.dropFirst(2)).map(\.layout) == SnapLayouts.all)
    }

    @Test func anywhereOnASuggestionMeansItsOpenZone() {
        var tracking = SnapLayoutBar()
        tracking.reset(tiles: SnapLayoutBar.tiles(others: [7, 9]))
        let frame = SnapLayoutBar.frame(visible: visible, count: tracking.tiles.count)
        #expect(frame.midX == 720)
        let first = SnapLayoutBar.tileRect(1)
        // The right half's top quarter is taken: the drop still goes to the open half.
        let point = CGPoint(x: frame.minX + first.minX + first.width * 0.8, y: frame.maxY - first.minY - 5)
        #expect(tracking.hit(point, in: frame) == SnapLayoutBar.Hit(tile: 1, zone: 0))
    }

    @Test func pushingAWindowToTheTopBringsTheBarDown() {
        #expect(tracked(to: CGPoint(x: 720, y: 860)) == 0)
        #expect(tracked(to: CGPoint(x: 720, y: 899)) == 0)
        // Not yet at the top, or off to the side.
        #expect(tracked(to: CGPoint(x: 720, y: 700)) == nil)
        #expect(tracked(to: CGPoint(x: 80, y: 880)) == nil)
    }

    @Test func slidingAWindowAlongTheTopDoesNotBringItDown() {
        #expect(tracked(to: CGPoint(x: 760, y: 852), from: CGPoint(x: 600, y: 852)) == nil)
        #expect(tracked(to: CGPoint(x: 760, y: 870), from: CGPoint(x: 600, y: 852)) == 0)
    }

    @Test func theBarStaysWhileTheMouseGoesDownIntoItAndGoesAfter() {
        var tracking = SnapLayoutBar()
        let start = CGPoint(x: 720, y: 450)
        tracking.track(mouse: CGPoint(x: 720, y: 880), start: start, screens: [screen], visibles: [visible])
        tracking.track(mouse: CGPoint(x: bar.minX + 10, y: bar.minY + 5), start: start, screens: [screen], visibles: [visible])
        #expect(tracking.screen == 0)
        tracking.track(mouse: CGPoint(x: bar.midX, y: bar.minY - 30), start: start, screens: [screen], visibles: [visible])
        #expect(tracking.screen == 0)
        tracking.track(mouse: CGPoint(x: bar.midX, y: bar.minY - 100), start: start, screens: [screen], visibles: [visible])
        #expect(tracking.screen == nil)
        tracking.track(mouse: CGPoint(x: 720, y: 880), start: start, screens: [screen], visibles: [visible])
        tracking.reset()
        #expect(tracking.screen == nil)
    }

    @Test func aTopEdgeSharedWithADisplayAboveShowsNoBar() {
        let above = CGRect(x: 0, y: 900, width: 1920, height: 1080)
        let screens = [screen, above]
        let visibles = [visible, CGRect(x: 0, y: 900, width: 1920, height: 1047)]
        #expect(tracked(to: CGPoint(x: 720, y: 880), screens: screens, visibles: visibles) == nil)
        // The display above has an open top of its own.
        #expect(tracked(to: CGPoint(x: 960, y: 1970), screens: screens, visibles: visibles) == 1)
    }

    @Test func theZoneUnderTheMouseIsFound() {
        func point(_ layout: Int, _ x: CGFloat, _ y: CGFloat) -> CGPoint {
            // `x` and `y` are shares across and down a picture.
            let tile = SnapLayoutBar.tileRect(layout)
            return CGPoint(x: bar.minX + tile.minX + x * tile.width, y: bar.maxY - tile.minY - y * tile.height)
        }
        #expect(SnapLayoutBar().hit(point(0, 0.25, 0.5), in: bar) == SnapLayoutBar.Hit(tile: 0, zone: 0))
        #expect(SnapLayoutBar().hit(point(0, 0.75, 0.5), in: bar) == SnapLayoutBar.Hit(tile: 0, zone: 1))
        #expect(SnapLayoutBar().hit(point(2, 0.75, 0.9), in: bar) == SnapLayoutBar.Hit(tile: 2, zone: 2))
        #expect(SnapLayoutBar().hit(point(3, 0.25, 0.75), in: bar) == SnapLayoutBar.Hit(tile: 3, zone: 2))
        #expect(SnapLayoutBar().hit(point(4, 0.5, 0.1), in: bar) == SnapLayoutBar.Hit(tile: 4, zone: 1))
        // The padding round the bar and the gaps between pictures are no zone.
        #expect(SnapLayoutBar().hit(CGPoint(x: bar.minX + 2, y: bar.midY), in: bar) == nil)
        let gap = SnapLayoutBar.tileRect(0).maxX + SnapLayoutBar.spacing / 2
        #expect(SnapLayoutBar().hit(CGPoint(x: bar.minX + gap, y: bar.midY), in: bar) == nil)
    }
}
