import CoreGraphics
import Testing
@testable import DockFlipKit

/// The Windows 11 style grid's layout.
@Suite("SwitcherGrid")
struct SwitcherGridTests {
    @Test func pictureFollowsTheWindowShapeWithinLimits() {
        func width(_ w: Double, _ h: Double) -> Double {
            SwitcherGrid.pictureWidth(windowSize: CGSize(width: w, height: h), height: 100)
        }
        #expect(abs(width(1600, 1000) - 160) < 0.001)
        // A tall, narrow window and a very wide one stay clickable tiles.
        #expect(abs(width(300, 1000) - 75) < 0.001)
        #expect(abs(width(5000, 500) - 190) < 0.001)
        // No size yet: 16:10.
        #expect(abs(width(0, 0) - 160) < 0.001)
    }

    @Test func tilesBreakIntoRowsThatFit() {
        // 100 + 10 + 100 + 10 + 100 = 320 fits in 330; the fourth tile starts a new row.
        let rows = SwitcherGrid.rows(widths: [100, 100, 100, 100, 100], maxWidth: 330, spacing: 10)
        #expect(rows == [0..<3, 3..<5])
    }

    @Test func aTileWiderThanARowGetsARowOfItsOwn() {
        let rows = SwitcherGrid.rows(widths: [500, 100, 100], maxWidth: 300, spacing: 10)
        #expect(rows == [0..<1, 1..<3])
        #expect(SwitcherGrid.rows(widths: [], maxWidth: 300, spacing: 10).isEmpty)
    }

    @Test func rowOfFindsTheSelectedTile() {
        let rows = [0..<3, 3..<5]
        #expect(SwitcherGrid.row(of: 0, in: rows) == 0)
        #expect(SwitcherGrid.row(of: 4, in: rows) == 1)
        #expect(SwitcherGrid.row(of: 5, in: rows) == nil)
    }

    @Test func visibleRowsKeepTheSelectedRowInSight() {
        // Few rows: all of them.
        #expect(SwitcherGrid.visibleRows(count: 2, selectedRow: 1, maxRows: 3) == 0..<2)
        // Many rows: the selected one near the middle, never past either end.
        #expect(SwitcherGrid.visibleRows(count: 10, selectedRow: 0, maxRows: 3) == 0..<3)
        #expect(SwitcherGrid.visibleRows(count: 10, selectedRow: 5, maxRows: 3) == 4..<7)
        #expect(SwitcherGrid.visibleRows(count: 10, selectedRow: 9, maxRows: 3) == 7..<10)
        #expect(SwitcherGrid.visibleRows(count: 0, selectedRow: 0, maxRows: 3).isEmpty)
        for selected in 0..<10 {
            #expect(SwitcherGrid.visibleRows(count: 10, selectedRow: selected, maxRows: 4).contains(selected))
        }
    }

    @Test func aLaptopScreenFitsThreeRowsOfFiveTiles() {
        // A MacBook Air's 1440 × 900, 16:10 windows: about 15 tiles in sight at once,
        // within the pictures the grid asks for as it opens.
        let metrics = SwitcherGrid.Metrics(screen: CGSize(width: 1440, height: 900))
        #expect(metrics.maxRows == 3)
        let width = metrics.tileWidth(windowSize: CGSize(width: 1440, height: 900))
        let rows = SwitcherGrid.rows(
            widths: Array(repeating: width, count: 30), maxWidth: metrics.maxRowWidth, spacing: SwitcherGrid.spacing)
        #expect(rows.first?.count == 5)
        #expect(metrics.maxRows * (rows.first?.count ?? 0) <= SwitcherGrid.previewBatch)
    }

    @Test func aTinyScreenStillDrawsARow() {
        let metrics = SwitcherGrid.Metrics(screen: CGSize(width: 200, height: 150))
        #expect(metrics.maxRows == 1)
        #expect(metrics.maxRowWidth >= 0)
    }
}
