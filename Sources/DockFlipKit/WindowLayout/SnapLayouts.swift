import CoreGraphics

/// One zone of a snap layout, as cells of a grid 12 columns wide and 2 rows high
/// over the usable area. Whole cells, not fractions: a third of 1440 points is
/// 480 exactly, where `1/3 + 1/3` in floating point lands a hair under 960 and
/// rounds down to 959.
public struct LayoutZone: Equatable {
    public static let columns = 12
    public static let rows = 2

    public let column: Int
    public let width: Int
    public let row: Int
    public let height: Int

    public init(column: Int, width: Int, row: Int = 0, height: Int = LayoutZone.rows) {
        self.column = column
        self.width = width
        self.row = row
        self.height = height
    }

    /// Whether `share` (0…1 across, 0…1 down from the top) falls in this zone.
    func contains(share: CGPoint) -> Bool {
        let x = share.x * CGFloat(Self.columns)
        let y = share.y * CGFloat(Self.rows)
        return x >= CGFloat(column) && x < CGFloat(column + width)
            && y >= CGFloat(row) && y < CGFloat(row + height)
    }
}

/// A snap layout: the zones it splits a display into, left to right, top to bottom.
public struct SnapLayout: Equatable {
    public let zones: [LayoutZone]
}

/// Windows 11's snap layouts, the ones a landscape display gets, pure and
/// unit-tested. `SnapLayoutBar` shows them while a window is dragged to the top.
/// Rectangles are in AX space (top-left origin).
public enum SnapLayouts {
    public static let all: [SnapLayout] = [
        // Halves.
        SnapLayout(zones: [LayoutZone(column: 0, width: 6), LayoutZone(column: 6, width: 6)]),
        // Two thirds and one third.
        SnapLayout(zones: [LayoutZone(column: 0, width: 8), LayoutZone(column: 8, width: 4)]),
        // A half and two quarters.
        SnapLayout(zones: [LayoutZone(column: 0, width: 6),
                           LayoutZone(column: 6, width: 6, row: 0, height: 1),
                           LayoutZone(column: 6, width: 6, row: 1, height: 1)]),
        // Quarters.
        SnapLayout(zones: [LayoutZone(column: 0, width: 6, row: 0, height: 1),
                           LayoutZone(column: 6, width: 6, row: 0, height: 1),
                           LayoutZone(column: 0, width: 6, row: 1, height: 1),
                           LayoutZone(column: 6, width: 6, row: 1, height: 1)]),
        // Thirds.
        SnapLayout(zones: [LayoutZone(column: 0, width: 4), LayoutZone(column: 4, width: 4),
                           LayoutZone(column: 8, width: 4)]),
        // A wide middle between two quarters.
        SnapLayout(zones: [LayoutZone(column: 0, width: 3), LayoutZone(column: 3, width: 6),
                           LayoutZone(column: 9, width: 3)]),
    ]

    /// The rectangle of `zone` inside the usable `area` of a display. Edges round
    /// down as `SnapEngine`'s halves do, so the two agree and neighbours share an edge.
    public static func rect(for zone: LayoutZone, in area: CGRect) -> CGRect {
        func x(_ column: Int) -> CGFloat {
            area.minX + (CGFloat(column) * area.width / CGFloat(LayoutZone.columns)).rounded(.down)
        }
        func y(_ row: Int) -> CGFloat {
            area.minY + (CGFloat(row) * area.height / CGFloat(LayoutZone.rows)).rounded(.down)
        }
        let minX = x(zone.column)
        let maxX = zone.column + zone.width >= LayoutZone.columns ? area.maxX : x(zone.column + zone.width)
        let minY = y(zone.row)
        let maxY = zone.row + zone.height >= LayoutZone.rows ? area.maxY : y(zone.row + zone.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The layout zone `frame` currently fills, if any, with `SnapEngine`'s tolerance
    /// for apps that round their sizes.
    public static func zone(matching frame: CGRect, in area: CGRect, tolerance: CGFloat = 24) -> LayoutZone? {
        for layout in all {
            for zone in layout.zones {
                let target = rect(for: zone, in: area)
                if abs(frame.minX - target.minX) <= tolerance
                    && abs(frame.minY - target.minY) <= tolerance
                    && abs(frame.width - target.width) <= tolerance
                    && abs(frame.height - target.height) <= tolerance {
                    return zone
                }
            }
        }
        return nil
    }

    /// The zone Snap Assist offers after a window lands in zone `index` of
    /// `layout`: the next one round, or nil for a layout of one zone.
    public static func nextZone(in layout: SnapLayout, after index: Int) -> LayoutZone? {
        guard layout.zones.count > 1, layout.zones.indices.contains(index) else { return nil }
        return layout.zones[(index + 1) % layout.zones.count]
    }
}
