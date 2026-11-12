import CoreGraphics

/// Windows 11's snap layouts bar, pure and unit-tested: while a window is dragged
/// up to the top of a display, a bar of layouts comes down at the top centre, and
/// letting go over one of a layout's zones puts the window there. Before the plain
/// layouts come snap suggestions, as on Windows: a layout with the most recently
/// used windows already in its other zones, so one drop arranges them all.
/// This holds which pictures the bar has, where it sits, which zone is under the
/// mouse, and when the bar shows and goes;
/// `SnapLayoutBarPanel` draws it and `SnapController` acts on it. Cocoa coordinates
/// (y grows upwards) unless a name says otherwise.
struct SnapLayoutBar {
    /// One layout's picture: about a display's shape.
    static let tile = CGSize(width: 64, height: 40)
    static let spacing: CGFloat = 8
    static let padding: CGFloat = 8
    /// The gap between the top of the usable area (under the menu bar) and the bar.
    static let topGap: CGFloat = 6
    /// How close to the top of the usable area the mouse comes before the bar shows.
    static let reveal: CGFloat = 30
    /// How far the mouse must have risen since the press. A window whose title bar
    /// is already at the top starts its drag inside `reveal`; sliding it sideways
    /// should not bring the bar down, pushing it up should.
    static let rise: CGFloat = 8
    /// How far the mouse may stray off the bar before it goes, so a hand that
    /// overshoots a zone does not lose the bar.
    static let keep: CGFloat = 48

    /// One picture on the bar: a plain layout, or a snap suggestion.
    struct Tile: Equatable {
        let layout: SnapLayout
        /// A suggestion's windows: zone index → the window it puts there. Empty
        /// for a plain layout. The dragged window takes the zone left over.
        let filled: [Int: CGWindowID]

        /// The zone a drop on this picture puts the dragged window in, for a suggestion.
        var openZone: Int? {
            filled.isEmpty ? nil : layout.zones.indices.first { filled[$0] == nil }
        }
    }

    /// A zone under the mouse: the picture's index in `tiles` and the zone's in its layout.
    struct Hit: Equatable {
        let tile: Int
        let zone: Int
    }

    /// The pictures this drag shows: the suggestions, then every layout.
    private(set) var tiles: [Tile] = SnapLayoutBar.tiles(others: [])
    /// The display (an index into the frames `track` was given) the bar shows on, nil while hidden.
    private(set) var screen: Int?

    /// The pictures for a drag, given the other windows that could go beside the
    /// dragged one, most recently used first: a half beside the last one, and a
    /// half beside the last two stacked, when there are that many; then the layouts.
    static func tiles(others: [CGWindowID]) -> [Tile] {
        var tiles: [Tile] = []
        if others.count >= 1 {
            tiles.append(Tile(layout: SnapLayouts.all[0], filled: [1: others[0]]))
        }
        if others.count >= 2 {
            tiles.append(Tile(layout: SnapLayouts.all[2], filled: [1: others[0], 2: others[1]]))
        }
        return tiles + SnapLayouts.all.map { Tile(layout: $0, filled: [:]) }
    }

    static func size(count: Int) -> CGSize {
        let count = CGFloat(count)
        return CGSize(width: count * tile.width + (count - 1) * spacing + 2 * padding,
                      height: tile.height + 2 * padding)
    }

    /// Where a bar of `count` pictures sits on a display with `visible` as its
    /// usable frame: centred across it, just under the menu bar.
    static func frame(visible: CGRect, count: Int) -> CGRect {
        let size = Self.size(count: count)
        return CGRect(x: (visible.midX - size.width / 2).rounded(), y: visible.maxY - topGap - size.height,
                      width: size.width, height: size.height)
    }

    /// Layout `index`'s picture inside the bar, top-left origin (as SwiftUI lays it out).
    static func tileRect(_ index: Int) -> CGRect {
        CGRect(x: padding + CGFloat(index) * (tile.width + spacing), y: padding,
               width: tile.width, height: tile.height)
    }

    /// `zone` inside a picture of `size`, top-left origin.
    static func rect(of zone: LayoutZone, in size: CGSize) -> CGRect {
        let column = size.width / CGFloat(LayoutZone.columns)
        let row = size.height / CGFloat(LayoutZone.rows)
        return CGRect(x: CGFloat(zone.column) * column, y: CGFloat(zone.row) * row,
                      width: CGFloat(zone.width) * column, height: CGFloat(zone.height) * row)
    }

    /// The zone under `point` on a bar at `frame`. The gaps drawn between a
    /// picture's zones count for their zones; the gaps between pictures do not.
    /// Anywhere on a suggestion means its open zone: the others are taken.
    func hit(_ point: CGPoint, in frame: CGRect) -> Hit? {
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        for (index, tile) in tiles.enumerated() {
            let rect = Self.tileRect(index)
            guard rect.contains(local) else { continue }
            if let open = tile.openZone { return Hit(tile: index, zone: open) }
            let share = CGPoint(x: (local.x - rect.minX) / rect.width, y: (local.y - rect.minY) / rect.height)
            guard let zone = tile.layout.zones.firstIndex(where: { $0.contains(share: share) }) else { return nil }
            return Hit(tile: index, zone: zone)
        }
        return nil
    }

    /// A new drag starts with the bar hidden, showing `tiles`.
    mutating func reset(tiles: [Tile] = SnapLayoutBar.tiles(others: [])) {
        self.tiles = tiles
        screen = nil
    }

    /// One drag event of a window drag, with the mouse at `mouse` after a press at
    /// `start`. `screens` and `visibles` are the displays' frames and usable frames,
    /// in the same order. Shows the bar when the mouse is pushed up to the top of a
    /// display, keeps it while the mouse stays near it, hides it otherwise.
    mutating func track(mouse: CGPoint, start: CGPoint, screens: [CGRect], visibles: [CGRect]) {
        guard let index = screens.firstIndex(where: { SnapZone.contains($0, mouse) }),
              visibles.indices.contains(index) else {
            screen = nil
            return
        }
        let bar = Self.frame(visible: visibles[index], count: tiles.count)
        let atTop = mouse.y >= visibles[index].maxY - Self.reveal
            && abs(mouse.x - bar.midX) <= bar.width / 2 + Self.keep
        let near = atTop || bar.insetBy(dx: -Self.keep, dy: -Self.keep).contains(mouse)
        if screen == index && near { return }

        // A top edge shared with a display above is the way there, not a place to
        // snap to: windows dragged across would bring the bar down every time.
        let above = CGPoint(x: mouse.x, y: screens[index].maxY + 2)
        let topIsOpen = !screens.contains { SnapZone.contains($0, above) }
        screen = topIsOpen && atTop && mouse.y - start.y >= Self.rise ? index : nil
    }
}
