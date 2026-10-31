import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapAssistGrid")
struct SnapAssistGridTests {
    /// The right half of a 1440 × 900 screen under the menu bar.
    private let half = SnapAssistGrid(region: CGSize(width: 720, height: 875))

    @Test func aHalfFitsSeveralCardsAndAQuarterSmallerOnes() {
        let quarter = SnapAssistGrid(region: CGSize(width: 720, height: 437))
        #expect(half.columns >= 2)
        #expect(half.capacity >= 6)
        #expect(quarter.capacity >= 2)
        #expect(quarter.pictureHeight < half.pictureHeight)
        #expect(quarter.pictureHeight >= 72)
    }

    @Test func cardsFitInsideTheRegion() {
        for size in [CGSize(width: 720, height: 875), CGSize(width: 1280, height: 1415), CGSize(width: 640, height: 400)] {
            let grid = SnapAssistGrid(region: size)
            let rows = (grid.capacity + grid.columns - 1) / grid.columns
            let width = Double(grid.columns) * grid.tileWidth + Double(grid.columns - 1) * SnapAssistGrid.spacing
            let tileHeight = grid.pictureHeight + SnapAssistGrid.headerHeight + 2 * SnapAssistGrid.tilePadding
            let height = Double(rows) * tileHeight + Double(rows - 1) * SnapAssistGrid.spacing
            #expect(width <= Double(size.width) - 2 * SnapAssistGrid.margin)
            #expect(height <= Double(size.height) - 2 * SnapAssistGrid.margin)
        }
    }

    @Test func aTinyRegionStillShowsOneCard() {
        let grid = SnapAssistGrid(region: CGSize(width: 100, height: 100))
        #expect(grid.columns == 1)
        #expect(grid.capacity == 1)
    }

    @Test func rowsHoldColumnsCardsEach() {
        let grid = SnapAssistGrid(region: CGSize(width: 720, height: 875))
        let rows = grid.rows(count: grid.columns + 1)
        #expect(rows == [0..<grid.columns, grid.columns..<(grid.columns + 1)])
        #expect(grid.rows(count: 0).isEmpty)
    }

    @Test func leftAndRightStepAcrossRowsAndStopAtTheEnds() {
        let columns = half.columns
        #expect(half.move(.right, from: 0, count: 5) == 1)
        #expect(half.move(.left, from: 0, count: 5) == 0)
        #expect(half.move(.right, from: 4, count: 5) == 4)
        #expect(half.move(.right, from: columns - 1, count: columns + 1) == columns)
    }

    @Test func upAndDownGoToTheCardAboveOrBelow() {
        let columns = half.columns
        let count = columns * 2 + 1
        #expect(half.move(.down, from: 0, count: count) == columns)
        #expect(half.move(.up, from: columns, count: count) == 0)
        #expect(half.move(.up, from: 0, count: count) == 0)
        // Into a shorter last row: its last card.
        #expect(half.move(.down, from: columns + 1, count: count) == columns * 2)
        #expect(half.move(.down, from: columns * 2, count: count) == columns * 2)
    }

    @Test func noCardsLeavesTheSelectionAtZero() {
        #expect(half.move(.right, from: 3, count: 0) == 0)
    }
}

@Suite("SnapAssistKey")
struct SnapAssistKeyTests {
    @Test func arrowsReturnAndEscapeDriveTheCards() {
        #expect(SnapAssistKey.from(keyCode: KeyCode.left, hasShortcutModifiers: false) == .move(.left))
        #expect(SnapAssistKey.from(keyCode: KeyCode.down, hasShortcutModifiers: false) == .move(.down))
        #expect(SnapAssistKey.from(keyCode: KeyCode.returnKey, hasShortcutModifiers: false) == .pick)
        #expect(SnapAssistKey.from(keyCode: KeyCode.keypadEnter, hasShortcutModifiers: false) == .pick)
        #expect(SnapAssistKey.from(keyCode: KeyCode.escape, hasShortcutModifiers: false) == .dismiss)
    }

    @Test func shortcutsAndOtherKeysGoBy() {
        // ⌃⌥← is the next snap, not a step through the cards.
        #expect(SnapAssistKey.from(keyCode: KeyCode.left, hasShortcutModifiers: true) == nil)
        #expect(SnapAssistKey.from(keyCode: KeyCode.d, hasShortcutModifiers: false) == nil)
    }
}
