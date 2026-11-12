import AppKit

/// The snap layouts bar's side of a window drag: the suggestions a drag offers,
/// the zone under the mouse, and what a drop on a layout or a suggestion does.
/// The rules are `SnapLayouts` and `SnapLayoutBar`.
extension SnapController {
    /// Where a window drag would snap the window if let go now. AX space.
    struct DragTarget {
        let rect: CGRect
        /// The usable area of the display it is on.
        let area: CGRect
        /// From an edge or a corner.
        let region: SnapRegion?
        /// From the layouts bar: the layout and the zone in it.
        let layout: (layout: SnapLayout, zone: Int)?
        /// From a snap suggestion: the other windows and where they go.
        let others: [(id: CGWindowID, rect: CGRect)]
    }

    /// Picks the snap suggestions for this drag: the most recently used windows
    /// that could go beside `id`, from memory. Once per drag, when it becomes a window drag.
    func prepareLayoutBar(for id: CGWindowID) {
        let others = registry.switcherWindows().filter { window in
            window.id != id && !window.isMinimized && !window.isAppHidden && !window.isOnOtherSpace
                && window.frame.width > 0 && window.frame.height > 0
        }.prefix(2)
        let tiles = SnapLayoutBar.tiles(others: others.map(\.id))
        barTracking.reset(tiles: tiles)
        var icons: [CGWindowID: NSImage] = [:]
        for window in others { icons[window.id] = window.icon }
        layoutBar.prepare(tiles, icons: icons)
    }

    /// Where the drag would snap the window: a zone of the layouts bar under the
    /// mouse first, then an edge or a corner. Shows, moves or hides the bar on the way.
    func dragTarget(at mouse: NSPoint, startMouse: NSPoint) -> DragTarget? {
        let screens = NSScreen.screens
        barTracking.track(mouse: mouse, start: startMouse,
                          screens: screens.map(\.frame), visibles: screens.map(\.visibleFrame))
        if let index = barTracking.screen, screens.indices.contains(index) {
            let frame = SnapLayoutBar.frame(visible: screens[index].visibleFrame, count: barTracking.tiles.count)
            let hit = barTracking.hit(mouse, in: frame)
            layoutBar.show(at: frame, hovered: hit)
            if let hit {
                let area = DisplayLayout.usableArea(of: screens[index])
                let tile = barTracking.tiles[hit.tile]
                let others: [(id: CGWindowID, rect: CGRect)] = tile.filled.keys.sorted().compactMap { zone in
                    guard let other = tile.filled[zone] else { return nil }
                    return (id: other, rect: SnapLayouts.rect(for: tile.layout.zones[zone], in: area))
                }
                return DragTarget(rect: SnapLayouts.rect(for: tile.layout.zones[hit.zone], in: area), area: area,
                                  region: nil, layout: (tile.layout, hit.zone), others: others)
            }
        } else {
            layoutBar.hide()
        }
        // The very top edge still maximizes with the bar down, as on Windows.
        guard let zone = Self.zone(at: mouse) else { return nil }
        let area = DisplayLayout.usableArea(of: zone.screen)
        return DragTarget(rect: SnapEngine.rect(for: zone.region, in: area), area: area, region: zone.region,
                          layout: nil, others: [])
    }

    /// A snap suggestion was taken: its windows fill their zones and come forward,
    /// each in order on its app's queue, and the dragged window ends up in front.
    /// Like any snap, ⌃⌥↓ gives a free window its frame back later.
    func arrange(_ others: [(id: CGWindowID, rect: CGRect)], around id: CGWindowID) {
        for other in others {
            if let frame = registry.knownFrame(of: other.id),
               let display = DisplayLayout.screenIndex(for: frame, in: NSScreen.screens),
               !Self.isSnapped(frame, in: DisplayLayout.usableArea(of: NSScreen.screens[display])) {
                remember(frame, for: other.id)
            }
            registry.focus(other.id)
            registry.setFrame(of: other.id, to: other.rect)
        }
        registry.focus(id)
    }

    /// After a drop on zone `zone` of `layout`, offers the other windows for the
    /// layout's next zone in `area`.
    func offerAssist(after zone: Int, of layout: SnapLayout, of id: CGWindowID, in area: CGRect) {
        guard let next = SnapLayouts.nextZone(in: layout, after: zone) else { return }
        let rect = SnapLayouts.rect(for: next, in: area)
        let windows = SnapAssist.candidates(from: registry.switcherWindows(), excluding: id)
            .prefix(SnapAssistPanel.capacity(for: rect))
        guard !windows.isEmpty else { return }
        assist.show(Array(windows), over: rect)
    }
}
