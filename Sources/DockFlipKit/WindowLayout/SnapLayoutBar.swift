import CoreGraphics

/// Windows 11's snap layouts bar, pure and unit-tested: while a window is dragged
/// up to the top of a display, a bar of layouts comes down at the top centre, and
/// letting go over one of a layout's zones puts the window there. This holds where
/// the bar sits, which zone is under the mouse, and when the bar shows and goes;
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

    /// A zone under the mouse: the layout's index in `SnapLayouts.all` and the zone's in it.
    struct Hit: Equatable {
        let layout: Int
        let zone: Int
    }

    /// The display (an index into the frames `track` was given) the bar shows on, nil while hidden.
    private(set) var screen: Int?

    static var size: CGSize {
        let count = CGFloat(SnapLayouts.all.count)
        return CGSize(width: count * tile.width + (count - 1) * spacing + 2 * padding,
                      height: tile.height + 2 * padding)
    }

    /// Where the bar sits on a display with `visible` as its usable frame: centred
    /// across it, just under the menu bar.
    static func frame(visible: CGRect) -> CGRect {
        let size = Self.size
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
    static func hit(_ point: CGPoint, in frame: CGRect) -> Hit? {
        let local = CGPoint(x: point.x - frame.minX, y: frame.maxY - point.y)
        for (index, layout) in SnapLayouts.all.enumerated() {
            let tile = tileRect(index)
            guard tile.contains(local) else { continue }
            let share = CGPoint(x: (local.x - tile.minX) / tile.width, y: (local.y - tile.minY) / tile.height)
            guard let zone = layout.zones.firstIndex(where: { $0.contains(share: share) }) else { return nil }
            return Hit(layout: index, zone: zone)
        }
        return nil
    }

    /// A mouse down: a new drag starts with the bar hidden.
    mutating func reset() {
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
        let bar = Self.frame(visible: visibles[index])
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
