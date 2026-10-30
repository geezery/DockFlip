import AppKit
import ApplicationServices
import CoreGraphics
import SwiftUI
import Testing
@testable import DockFlipKit

@Suite("WindowListLayout")
struct WindowListLayoutTests {
    func tabs(_ count: Int, window: CGWindowID = 1, selected: Int? = nil) -> [BrowserTab] {
        (0..<count).map { index in
            BrowserTab(
                id: "\(window):\(index)", windowID: window, index: index,
                title: "Tab \(index)", site: nil, fullTitle: "Tab \(index)",
                isSelected: index == selected, element: AXUIElementCreateSystemWide()
            )
        }
    }

    func row(_ id: CGWindowID, tabs: [BrowserTab] = []) -> WindowListRow {
        WindowListRow(
            id: id, title: "Window \(id)", icon: nil, minimap: nil,
            isMinimized: false, isOnOtherSpace: false, isActive: false,
            tint: .gray, tabs: tabs
        )
    }

    @Test func singleTabIsNotListed() {
        let (shown, hidden) = WindowListLayout.visibleTabs(of: row(1, tabs: tabs(1)), expanded: false)
        #expect(shown.isEmpty)
        #expect(hidden == 0)
    }

    @Test func shortTabListIsShownInFull() {
        let (shown, hidden) = WindowListLayout.visibleTabs(of: row(1, tabs: tabs(8)), expanded: false)
        #expect(shown.count == 8)
        #expect(hidden == 0)
    }

    @Test func longTabListFolds() {
        let (shown, hidden) = WindowListLayout.visibleTabs(of: row(1, tabs: tabs(12)), expanded: false)
        #expect(shown.map(\.index) == Array(0..<7))
        #expect(hidden == 5)
    }

    @Test func foldedListKeepsSelectedTab() {
        let (shown, hidden) = WindowListLayout.visibleTabs(of: row(1, tabs: tabs(12, selected: 10)), expanded: false)
        #expect(shown.map(\.index) == Array(0..<7) + [10])
        #expect(hidden == 4)
    }

    @Test func expandedListShowsEveryTab() {
        let (shown, hidden) = WindowListLayout.visibleTabs(of: row(1, tabs: tabs(12)), expanded: true)
        #expect(shown.count == 12)
        #expect(hidden == 0)
    }

    @Test func shortTabListHasNoFoldControl() {
        #expect(WindowListLayout.foldControl(of: row(1, tabs: tabs(8)), expanded: false) == nil)
        #expect(WindowListLayout.foldControl(of: row(1, tabs: tabs(8)), expanded: true) == nil)
    }

    @Test func foldedListOffersShowAll() {
        #expect(WindowListLayout.foldControl(of: row(1, tabs: tabs(12)), expanded: false) == .showAll(12))
    }

    @Test func expandedListOffersShowFewer() {
        #expect(WindowListLayout.foldControl(of: row(1, tabs: tabs(12)), expanded: true) == .showFewer)
    }

    @Test func showFewerFoldsBackToEightLines() {
        let twelve = row(1, tabs: tabs(12))
        var expanded: Set<CGWindowID> = [1]
        #expect(WindowListLayout.foldControl(of: twelve, expanded: expanded.contains(1)) == .showFewer)
        // "Show fewer" calls toggleExpanded, which takes the window out of `expanded`.
        expanded.remove(1)
        let (shown, hidden) = WindowListLayout.visibleTabs(of: twelve, expanded: expanded.contains(1))
        #expect(shown.map(\.index) == Array(0..<7))
        #expect(hidden == 5)
        #expect(WindowListLayout.foldControl(of: twelve, expanded: expanded.contains(1)) == .showAll(12))
        // Seven tabs and "Show all 12 tabs": eight lines.
        let size = WindowListLayout.size(rows: [twelve], expanded: expanded, previews: false)
        #expect(size.height == 46 + 48 + 8 * 28 + 6)
    }

    @Test func blockCountsTheFoldLine() {
        // What "N more windows" counts with: the open list's "Show fewer" line too.
        let twelve = row(1, tabs: tabs(12))
        #expect(WindowListLayout.blockHeight(of: twelve, expanded: true) == 48 + 13 * 28 + 6)
        #expect(WindowListLayout.blockHeight(of: twelve, expanded: false) == 48 + 8 * 28 + 6)
        #expect(WindowListLayout.blockHeight(of: row(1, tabs: tabs(8)), expanded: true) == 48 + 8 * 28 + 6)
    }

    @Test func cardsOnlyWithPreviewsFewWindowsAndNoTabs() {
        let three = [row(1), row(2), row(3)]
        #expect(WindowListLayout.usesCards(rows: three, previews: true))
        #expect(!WindowListLayout.usesCards(rows: three, previews: false))
        #expect(!WindowListLayout.usesCards(rows: (1...6).map { row($0) }, previews: true))
        #expect(!WindowListLayout.usesCards(rows: [row(1), row(2, tabs: tabs(2, window: 2))], previews: true))
    }

    @Test func emptyListSize() {
        #expect(WindowListLayout.size(rows: [], expanded: [], previews: false) == NSSize(width: 220, height: 44))
    }

    @Test func cardsSize() {
        let size = WindowListLayout.size(rows: [row(1), row(2), row(3)], expanded: [], previews: true)
        #expect(size == NSSize(width: 3 * 212 + 16, height: 36 + 156 + 12))
    }

    @Test func plainListSize() {
        let size = WindowListLayout.size(rows: [row(1), row(2)], expanded: [], previews: false)
        #expect(size == NSSize(width: 320, height: 46 + 2 * 48))
    }

    @Test func listCountsAtMostTenRows() {
        // Ten rows, and room for "2 more windows" under them instead of the 10-point margin.
        let size = WindowListLayout.size(rows: (1...12).map { row($0) }, expanded: [], previews: false)
        #expect(size.height == 36 + 10 * 48 + 24)
    }

    @Test func fourteenWindowsSayFourMoreBelow() {
        let rows = (1...14).map { row($0) }
        let top = WindowListLayout.listHeight(rows: rows, expanded: [], previews: false)
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: top) == 4)
        // Scrolled two windows down, two are left; at the end, none.
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: top + 2 * 48) == 2)
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: 14 * 48) == 0)
    }

    @Test func tenWindowsFitWithNothingBelow() {
        let rows = (1...10).map { row($0) }
        let top = WindowListLayout.listHeight(rows: rows, expanded: [], previews: false)
        #expect(top == 10 + 10 * 48)
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: top) == 0)
    }

    @Test func partlyShownWindowCountsAsBelow() {
        let rows = (1...3).map { row($0) }
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: 2 * 48 + 20) == 1)
        // A fractional offset a hair short of the end still counts as the end.
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: 3 * 48 - 0.3) == 0)
    }

    @Test func tabsCountTowardsWhatIsBelow() {
        // Three windows of twelve tabs overflow the capped list well before ten rows.
        let rows = (1...3).map { row($0, tabs: tabs(12, window: $0)) }
        let top = WindowListLayout.listHeight(rows: rows, expanded: [], previews: true)
        #expect(top == 370 - 36)
        // Each window with its folded tabs is 48 + 8 * 28 + 6 = 278 high: the second is cut, the third unseen.
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [], visibleBottom: top) == 2)
        #expect(WindowListLayout.windowsBelow(rows: rows, expanded: [1], visibleBottom: top) == 3)
    }

    @Test func tabListSize() {
        let three = WindowListLayout.size(rows: [row(1, tabs: tabs(3))], expanded: [], previews: false)
        #expect(three == NSSize(width: 400, height: 46 + 48 + 3 * 28 + 6))
        // Twelve tabs fold to seven lines plus "Show all 12 tabs".
        let folded = WindowListLayout.size(rows: [row(1, tabs: tabs(12))], expanded: [], previews: false)
        #expect(folded.height == 46 + 48 + 8 * 28 + 6)
        // Open, all twelve plus "Show fewer".
        let expanded = WindowListLayout.size(rows: [row(1, tabs: tabs(12))], expanded: [1], previews: false)
        #expect(expanded.height == 46 + 48 + 13 * 28 + 6)
        // Eight tabs fit unfolded and get neither line, open or not.
        let eight = WindowListLayout.size(rows: [row(1, tabs: tabs(8))], expanded: [1], previews: false)
        #expect(eight.height == 46 + 48 + 8 * 28 + 6)
    }

    @Test func tabListWithPeekPicture() {
        let size = WindowListLayout.size(rows: [row(1, tabs: tabs(3))], expanded: [], previews: true)
        #expect(size == NSSize(width: 400, height: 46 + 48 + 3 * 28 + 6 + 230 + 6))
    }

    @Test func heightIsCapped() {
        let rows = (1...10).map { row($0, tabs: tabs(12, window: $0)) }
        #expect(WindowListLayout.size(rows: rows, expanded: [], previews: false).height == 600)
        #expect(WindowListLayout.size(rows: rows, expanded: [], previews: true).height == 370 + 230 + 6)
    }
}
