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

@Suite("SnapEngine")
struct SnapEngineTests {
    let area = CGRect(x: 0, y: 25, width: 1440, height: 827)

    @Test func windowsKeyboardSequence() {
        // Free → left half → top-left quarter → left half → bottom-left → minimize.
        #expect(SnapEngine.action(for: .left, current: nil, display: 0, displayCount: 1) == .snap(.leftHalf, display: 0))
        #expect(SnapEngine.action(for: .up, current: .leftHalf, display: 0, displayCount: 1) == .snap(.topLeft, display: 0))
        #expect(SnapEngine.action(for: .down, current: .topLeft, display: 0, displayCount: 1) == .snap(.leftHalf, display: 0))
        #expect(SnapEngine.action(for: .down, current: .leftHalf, display: 0, displayCount: 1) == .snap(.bottomLeft, display: 0))
        #expect(SnapEngine.action(for: .down, current: .bottomLeft, display: 0, displayCount: 1) == .minimize)
    }

    @Test func maximizeAndRestore() {
        #expect(SnapEngine.action(for: .up, current: nil, display: 0, displayCount: 1) == .snap(.maximized, display: 0))
        #expect(SnapEngine.action(for: .down, current: .maximized, display: 0, displayCount: 1) == .restore)
        #expect(SnapEngine.action(for: .down, current: nil, display: 0, displayCount: 1) == .minimize)
        #expect(SnapEngine.action(for: .left, current: .rightHalf, display: 0, displayCount: 1) == .restore)
    }

    @Test func crossesToNeighbouringDisplay() {
        #expect(SnapEngine.action(for: .right, current: .rightHalf, display: 0, displayCount: 2) == .snap(.leftHalf, display: 1))
        #expect(SnapEngine.action(for: .left, current: .leftHalf, display: 1, displayCount: 2) == .snap(.rightHalf, display: 0))
        #expect(SnapEngine.action(for: .right, current: .rightHalf, display: 1, displayCount: 2) == SnapAction.none)
    }

    @Test func rectsTileTheArea() {
        let left = SnapEngine.rect(for: .leftHalf, in: area)
        let right = SnapEngine.rect(for: .rightHalf, in: area)
        #expect(left.maxX == right.minX)
        #expect(left.width + right.width == area.width)
        let topRight = SnapEngine.rect(for: .topRight, in: area)
        let bottomRight = SnapEngine.rect(for: .bottomRight, in: area)
        #expect(topRight.maxY == bottomRight.minY)
        #expect(bottomRight.maxY == area.maxY)
    }

    @Test func detectsRegionWithTolerance() {
        let snapped = SnapEngine.rect(for: .leftHalf, in: area).insetBy(dx: 3, dy: 5)
        #expect(SnapEngine.region(matching: snapped, in: area) == .leftHalf)
        #expect(SnapEngine.region(matching: CGRect(x: 200, y: 200, width: 600, height: 400), in: area) == nil)
    }

    @Test func translateKeepsWindowOnTarget() {
        let source = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let target = CGRect(x: 1000, y: 0, width: 2000, height: 1000)
        let moved = SnapEngine.translate(CGRect(x: 500, y: 400, width: 400, height: 300), from: source, to: target)
        #expect(target.contains(moved))
        #expect(moved.size == CGSize(width: 400, height: 300))
    }
}

@Suite("CleanupEngine")
struct CleanupEngineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    @Test func suggestsOnlyLongUnusedWindowsOldestFirst() {
        let windows = [
            CleanupEngine.WindowInput(id: 1, bundleID: "com.microsoft.teams2", lastUsed: now.addingTimeInterval(-5 * day)),
            CleanupEngine.WindowInput(id: 2, bundleID: "com.apple.Safari", lastUsed: now.addingTimeInterval(-1 * day)),
            CleanupEngine.WindowInput(id: 3, bundleID: "com.apple.Preview", lastUsed: now.addingTimeInterval(-9 * day))
        ]
        #expect(CleanupEngine.idleWindows(windows, now: now, keep: []) == [3, 1])
        #expect(CleanupEngine.idleWindows(windows, now: now, keep: ["com.apple.Preview"]) == [1])
    }

    @Test func suggestsWindowlessAppsButNeverFinderOrFrontmost() {
        let old = now.addingTimeInterval(-2 * day)
        let apps = [
            CleanupEngine.AppInput(pid: 10, bundleID: "com.apple.finder", hasWindows: false, isFrontmost: false, lastUsed: old),
            CleanupEngine.AppInput(pid: 11, bundleID: "com.apple.TextEdit", hasWindows: false, isFrontmost: false, lastUsed: old),
            CleanupEngine.AppInput(pid: 12, bundleID: "com.apple.Notes", hasWindows: true, isFrontmost: false, lastUsed: old),
            CleanupEngine.AppInput(pid: 13, bundleID: "com.apple.Music", hasWindows: false, isFrontmost: true, lastUsed: old),
            CleanupEngine.AppInput(pid: 14, bundleID: "com.apple.Maps", hasWindows: false, isFrontmost: false, lastUsed: now)
        ]
        #expect(CleanupEngine.idleApps(apps, now: now, keep: []) == [11])
    }
}

