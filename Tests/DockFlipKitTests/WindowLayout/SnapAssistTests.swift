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
