import CoreGraphics
import Testing
@testable import PlinthKit

@Suite("MRUList")
struct MRUListTests {
    @Test func initRemovesDuplicates() {
        #expect(MRUList([1, 2, 1, 3]).items == [1, 2, 3])
    }

    @Test func moveToFront() {
        var list = MRUList([1, 2, 3])
        list.moveToFront(3)
        #expect(list.items == [3, 1, 2])
        list.moveToFront(4)
        #expect(list.items == [4, 3, 1, 2])
    }

    @Test func appendAndRemove() {
        var list = MRUList([1])
        list.appendIfMissing(2)
        list.appendIfMissing(1)
        #expect(list.items == [1, 2])
        list.remove(1)
        #expect(list.items == [2])
    }
}

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

@Suite("Geometry")
struct GeometryTests {
    // Primary 1440×900 at the origin, a second 1920×1080 display to its right,
    // bottom-aligned (Cocoa coordinates).
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func cocoaToAXRoundTrip() {
        let ax = Geometry.axRect(fromCocoa: secondary, primaryHeight: primary.height)
        #expect(ax == CGRect(x: 1440, y: -180, width: 1920, height: 1080))
        #expect(Geometry.cocoaRect(fromAX: ax, primaryHeight: primary.height) == secondary)
    }

    @Test func picksScreenWithMostOverlap() {
        let screens = [primary, secondary].map { Geometry.axRect(fromCocoa: $0, primaryHeight: primary.height) }
        let window = CGRect(x: 1300, y: 100, width: 800, height: 600)
        #expect(Geometry.bestScreenIndex(for: window, screens: screens) == 1)
        #expect(Geometry.bestScreenIndex(for: CGRect(x: -5000, y: 0, width: 10, height: 10), screens: screens) == nil)
    }

    @Test func normalizesWithinScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = Geometry.normalized(CGRect(x: 0, y: 0, width: 500, height: 500), in: screen)
        #expect(rect == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }
}
