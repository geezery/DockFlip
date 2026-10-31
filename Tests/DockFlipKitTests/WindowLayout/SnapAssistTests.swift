import AppKit
import Testing
@testable import DockFlipKit

@Suite("SnapAssist")
struct SnapAssistTests {
    private func window(_ id: CGWindowID, frame: CGRect = CGRect(x: 0, y: 25, width: 900, height: 700),
                        minimized: Bool = false, hidden: Bool = false, otherSpace: Bool = false) -> WindowSnapshot {
        var snapshot = WindowSnapshot(
            id: id, pid: 42, bundleID: "com.apple.TextEdit", appName: "TextEdit", icon: nil,
            title: "", frame: frame, isMinimized: minimized, isAppHidden: hidden
        )
        snapshot.isOnOtherSpace = otherSpace
        return snapshot
    }

    @Test func halvesLeaveTheOtherHalf() {
        #expect(SnapAssist.remainingRegion(after: .leftHalf) == .rightHalf)
        #expect(SnapAssist.remainingRegion(after: .rightHalf) == .leftHalf)
    }

    @Test func quartersLeaveTheRestOfTheirHalf() {
        #expect(SnapAssist.remainingRegion(after: .topLeft) == .bottomLeft)
        #expect(SnapAssist.remainingRegion(after: .bottomLeft) == .topLeft)
        #expect(SnapAssist.remainingRegion(after: .topRight) == .bottomRight)
        #expect(SnapAssist.remainingRegion(after: .bottomRight) == .topRight)
    }

    @Test func maximizedLeavesNothing() {
        #expect(SnapAssist.remainingRegion(after: .maximized) == nil)
    }

    @Test func candidatesKeepOrderAndDropTheSnappedWindow() {
        let windows = [window(3), window(1), window(2)]
        let ids = SnapAssist.candidates(from: windows, excluding: 1).map(\.id)
        #expect(ids == [3, 2])
    }

    @Test func candidatesOfferMinimizedAndHiddenButNotOtherSpacesOrUnreadFrames() {
        let windows = [
            window(1),
            window(2, frame: .zero, minimized: true),
            window(3, hidden: true),
            window(4, otherSpace: true),
            window(5, frame: .zero),
        ]
        let ids = SnapAssist.candidates(from: windows, excluding: 1).map(\.id)
        #expect(ids == [2, 3])
    }
}

extension SnapAssistTests {
    @Test func noWindowsOrOnlyTheSnappedOneOffersNothing() {
        #expect(SnapAssist.candidates(from: [], excluding: 1).isEmpty)
        #expect(SnapAssist.candidates(from: [window(1)], excluding: 1).isEmpty)
    }
}

extension SnapAssistTests {
    @Test func offerGivesTheRegionLeftAndTheOtherWindows() {
        let offer = SnapAssist.offer(after: .leftHalf, snappedID: 1, windows: [window(1), window(2), window(3)], limit: 8)
        #expect(offer?.region == .rightHalf)
        #expect(offer?.windows.map(\.id) == [2, 3])
    }

    @Test func offerKeepsTheMostRecentlyUsedWithinTheLimit() {
        let offer = SnapAssist.offer(after: .topLeft, snappedID: 1, windows: [window(1), window(2), window(3), window(4)], limit: 2)
        #expect(offer?.region == .bottomLeft)
        #expect(offer?.windows.map(\.id) == [2, 3])
    }

    @Test func nothingIsOfferedAfterMaximizingOrWithNoOtherWindow() {
        #expect(SnapAssist.offer(after: .maximized, snappedID: 1, windows: [window(1), window(2)], limit: 8) == nil)
        #expect(SnapAssist.offer(after: .rightHalf, snappedID: 1, windows: [window(1), window(4, otherSpace: true)], limit: 8) == nil)
        #expect(SnapAssist.offer(after: .rightHalf, snappedID: 1, windows: [window(1), window(2)], limit: 0) == nil)
    }
}
