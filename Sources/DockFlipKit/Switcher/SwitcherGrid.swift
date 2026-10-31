import CoreGraphics
import Foundation

/// The layout of the Windows 11 style ⌘Tab grid (`SwitcherGridView`). Pure, unit-tested.
///
/// As on Windows 11, every tile has the same picture height and a width that
/// follows its window's shape; tiles fill rows left to right, the rows centred in
/// one panel. With more rows than fit, only those around the selected tile are
/// drawn, so ⌘Tab with dozens of windows opens as fast as with a few.
public enum SwitcherGrid {
    /// A picture's width over its height, kept within this: a very tall or very
    /// wide window still gets a tile one can see and click.
    public static let aspectRange: ClosedRange<Double> = 0.75...1.9
    /// The grid draws many windows at once, so it asks for more pictures as it
    /// opens than the stack does (`SwitcherPreviews.toCaptureAround`).
    public static let previewBatch = 24

    /// Around each tile's icon, title and picture.
    public static let tilePadding = 8.0
    /// The icon and title above the picture, with the gap under them.
    public static let headerHeight = 24.0
    /// Between tiles and between rows.
    public static let spacing = 10.0
    /// Between the panel's edge and the tiles.
    public static let panelPadding = 16.0

    /// The sizes that follow the screen, for a screen of `screen` points.
    public struct Metrics: Equatable, Sendable {
        /// The height of every window picture.
        public let pictureHeight: Double
        /// The widest a row of tiles gets.
        public let maxRowWidth: Double
        /// The most rows drawn at once.
        public let maxRows: Int

        public init(screen: CGSize) {
            let width = Double(screen.width)
            let height = Double(screen.height)
            let picture = min(max(height * 0.15, 96), 160)
            pictureHeight = picture
            // The panel takes at most 90 % of the screen's width and 70 % of its height.
            maxRowWidth = max(width * 0.9 - 2 * SwitcherGrid.panelPadding, 0)
            let tileHeight = picture + SwitcherGrid.headerHeight + 2 * SwitcherGrid.tilePadding
            let room = height * 0.7 - 2 * SwitcherGrid.panelPadding + SwitcherGrid.spacing
            maxRows = min(max(Int(room / (tileHeight + SwitcherGrid.spacing)), 1), 4)
        }

        /// The full width of the tile for a window of `windowSize`, padding included.
        public func tileWidth(windowSize: CGSize) -> Double {
            SwitcherGrid.pictureWidth(windowSize: windowSize, height: pictureHeight) + 2 * SwitcherGrid.tilePadding
        }
    }

    /// The width of a window's picture at `height`, in the window's own shape
    /// within `aspectRange`. A window with no size yet gets a 16:10 picture.
    public static func pictureWidth(windowSize: CGSize, height: Double) -> Double {
        let w = Double(windowSize.width)
        let h = Double(windowSize.height)
        let aspect = (w > 0 && h > 0) ? w / h : 1.6
        return height * min(max(aspect, aspectRange.lowerBound), aspectRange.upperBound)
    }

    /// Tiles of `widths` broken into rows no wider than `maxWidth`, in order.
    /// Every row holds at least one tile, even one wider than `maxWidth`.
    public static func rows(widths: [Double], maxWidth: Double, spacing: Double) -> [Range<Int>] {
        var rows: [Range<Int>] = []
        var start = 0
        var used = 0.0
        for (index, width) in widths.enumerated() {
            if index > start, used + spacing + width > maxWidth {
                rows.append(start..<index)
                start = index
                used = width
            } else {
                used += (index > start ? spacing : 0) + width
            }
        }
        if start < widths.count { rows.append(start..<widths.count) }
        return rows
    }

    /// The row that holds tile `index`, or nil when no row does.
    public static func row(of index: Int, in rows: [Range<Int>]) -> Int? {
        rows.firstIndex { $0.contains(index) }
    }

    /// The rows to draw: at most `maxRows`, the selected one among them, as near
    /// the middle as the first and last rows allow.
    public static func visibleRows(count: Int, selectedRow: Int, maxRows: Int) -> Range<Int> {
        guard count > 0, maxRows > 0 else { return 0..<0 }
        let shown = min(count, maxRows)
        let first = min(max(0, selectedRow - (shown - 1) / 2), count - shown)
        return first..<(first + shown)
    }
}
