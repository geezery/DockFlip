import CoreGraphics
import Foundation
import Testing
@testable import DockFlipKit

@Suite("PlacementLayouts")
struct PlacementLayoutsTests {
    let laptop = "A@0,0,1512x982"
    let docked = "A@0,0,1512x982|B@1512,0,2560x1440"

    /// A restart of DockFlip reads back exactly what it saved: the windows on both
    /// displays, and which display set was saved last.
    @Test func layoutsSurviveTheSavedForm() throws {
        var layouts = PlacementLayouts()
        layouts.set([1: CGRect(x: 0, y: 25, width: 800, height: 600)], for: laptop)
        layouts.set([
            1: CGRect(x: 1600, y: 40, width: 1200, height: 900),
            2: CGRect(x: 10.5, y: 30, width: 640, height: 480),
        ], for: docked)

        // Through a property list file, as UserDefaults keeps it on disk.
        let data = try PropertyListSerialization.data(fromPropertyList: layouts.propertyList, format: .binary, options: 0)
        let readBack = try PropertyListSerialization.propertyList(from: data, format: nil)

        let restored = PlacementLayouts(propertyList: readBack)
        #expect(restored == layouts)
        #expect(restored.order == [laptop, docked])
        #expect(restored[docked]?[2] == CGRect(x: 10.5, y: 30, width: 640, height: 480))
    }

    @Test func nothingOrSomethingElseSavedReadsAsNoLayouts() {
        #expect(PlacementLayouts(propertyList: nil) == PlacementLayouts())
        #expect(PlacementLayouts(propertyList: "garbage") == PlacementLayouts())
        let broken: [[String: Any]] = [
            ["signature": laptop, "frames": [
                "x": [1.0, 2, 3, 4], "7": [1.0, 2], "8": [Double.nan, 2, 3, 4], "9": [1.0, 2, 0, 4],
            ]],
            ["frames": ["1": [1.0, 2, 3, 4]]],
        ]
        let restored = PlacementLayouts(propertyList: broken)
        #expect(restored.order == [laptop])
        #expect(restored[laptop] == [:])
    }

    @Test func onlyTheNewestDisplaySetsAreKept() {
        var layouts = PlacementLayouts()
        for n in 0..<(PlacementLayouts.maxLayouts + 2) {
            layouts.set([1: .zero], for: "set\(n)")
        }
        layouts.set([1: .zero], for: "set3") // saved again: newest now
        #expect(layouts.order.count == PlacementLayouts.maxLayouts)
        #expect(layouts["set0"] == nil)
        #expect(layouts["set1"] == nil)
        #expect(layouts.order.last == "set3")
        #expect(layouts.order.first == "set2")
    }

    @Test func windowsThatAreGoneAreForgottenInEveryDisplaySet() {
        var layouts = PlacementLayouts()
        layouts.set([1: .zero, 2: .zero], for: laptop)
        layouts.set([2: .zero, 3: .zero], for: docked)
        layouts.keepOnly([2])
        #expect(layouts[laptop] == [2: .zero])
        #expect(layouts[docked] == [2: .zero])
        #expect(layouts.order == [laptop, docked])
    }

    /// A restart in the middle of a display change: saving paused, so the last save was
    /// for the displays before it. Starting with other displays is the change, not a layout.
    @Test func startingWithOtherDisplaysThanTheLastSaveIsADisplayChange() throws {
        var layouts = PlacementLayouts()
        #expect(!layouts.isDisplayChange(to: laptop)) // nothing saved: first launch, new boot

        layouts.set([1: CGRect(x: 1600, y: 40, width: 1200, height: 900)], for: docked)
        layouts.set([1: CGRect(x: 0, y: 25, width: 800, height: 600)], for: laptop)
        #expect(!layouts.isDisplayChange(to: laptop))
        #expect(layouts.isDisplayChange(to: docked)) // plugged in, then DockFlip restarted

        // The new launch reads the order back from the saved form.
        let data = try PropertyListSerialization.data(fromPropertyList: layouts.propertyList, format: .binary, options: 0)
        let restored = PlacementLayouts(propertyList: try PropertyListSerialization.propertyList(from: data, format: nil))
        #expect(restored.isDisplayChange(to: docked))
        #expect(!restored.isDisplayChange(to: laptop))
    }
}
