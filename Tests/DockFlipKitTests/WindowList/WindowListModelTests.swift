import CoreGraphics
import SwiftUI
import Testing
@testable import DockFlipKit

/// One panel and one scroll view serve every app's list, so a new list must
/// not start where the last one was scrolled to.
@Suite("WindowListModel: a new list")
@MainActor
struct WindowListModelTests {
    func rows(_ count: Int) -> [WindowListRow] {
        (1...count).map { id in
            WindowListRow(
                id: CGWindowID(id), title: "Window \(id)", icon: nil, minimap: nil,
                isMinimized: false, isOnOtherSpace: false, isActive: false,
                tint: .gray, tabs: []
            )
        }
    }

    @Test func nextAppsListStartsAtTheTop() {
        let model = WindowListModel()
        // Finder's fourteen windows, scrolled to the end.
        model.rows = rows(14)
        model.listBottom = 14 * 48
        #expect(model.windowsBelow == 0)
        let finderList = model.listID

        // The mouse rests on an app with twelve windows.
        model.startNewList()
        model.rows = rows(12)
        // A new scroll view, at its top: ten windows shown, two below.
        #expect(model.listID != finderList)
        #expect(model.listBottom == nil)
        #expect(model.windowsBelow == 2)
    }

    @Test func newListForgetsTheLastOnesState() {
        let model = WindowListModel()
        model.rows = rows(3)
        model.expanded = [1]
        model.peekWindow = 2
        model.hoveringPeek = true
        model.startNewList()
        #expect(model.expanded.isEmpty)
        #expect(model.peekWindow == nil)
        #expect(!model.hoveringPeek)
        #expect(model.thumbnails.isEmpty)
    }
}
