import CoreGraphics
import SwiftUI
import Testing
@testable import DockFlipKit

/// One panel and one scroll view serve every app's list, so a new list must
/// not start where the last one was scrolled to, nor with a line still lit.
@Suite("WindowListModel: a new list and hover")
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

    /// "Show all N tabs" lights up under the mouse like a tab row does.
    @Test func foldLineLightsUnderTheMouse() {
        let model = WindowListModel()
        model.setHoveredFold(7, true)
        #expect(model.hoveredFold == 7)
        // Onto the next window's fold line: its enter can come before this one's exit.
        model.setHoveredFold(9, true)
        model.setHoveredFold(7, false)
        #expect(model.hoveredFold == 9)
        model.setHoveredFold(9, false)
        #expect(model.hoveredFold == nil)
    }

    /// A click hides the panel before the mouse leaves the line, so nothing
    /// may still be lit when the list opens again.
    @Test func newListStartsWithNothingLit() {
        let model = WindowListModel()
        model.setHovered(3, true)
        model.setHoveredTab("tab", window: 3, true)
        model.setHoveredFold(3, true)
        model.startNewList()
        #expect(model.hoveredRow == nil)
        #expect(model.hoveredTab == nil)
        #expect(model.hoveredFold == nil)
    }
}
