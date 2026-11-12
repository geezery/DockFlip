import AppKit
import SwiftUI

/// What the layouts bar draws; `SnapLayoutBarPanel` changes it, the view only reads it.
@MainActor
final class SnapLayoutBarModel: ObservableObject {
    @Published var tiles: [SnapLayoutBar.Tile] = SnapLayoutBar.tiles(others: [])
    /// The app icons shown in a suggestion's taken zones, by window.
    @Published var icons: [CGWindowID: NSImage] = [:]
    @Published var hovered: SnapLayoutBar.Hit?
}

/// The snap layouts bar's panel, shown while a window is dragged to the top of a
/// display. The mouse never reaches it: the drag belongs to the window's app, so
/// `SnapController` works out the zone under the mouse from `SnapLayoutBar` and
/// tells the panel which one to light up.
@MainActor
final class SnapLayoutBarPanel {
    private let model = SnapLayoutBarModel()
    private var panel: NSPanel?

    /// The pictures and the suggested windows' app icons for the next drag.
    func prepare(_ tiles: [SnapLayoutBar.Tile], icons: [CGWindowID: NSImage]) {
        model.tiles = tiles
        model.icons = icons
    }

    /// Shows the bar at `frame` (Cocoa space) with `hovered` lit up. Coming in, it
    /// slides down a little and fades in, as Windows' does.
    func show(at frame: CGRect, hovered: SnapLayoutBar.Hit?) {
        // Drag events come many times a second; SwiftUI redraws only on a change.
        if model.hovered != hovered { model.hovered = hovered }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if panel.isVisible {
            // The same display: nothing to move. Another one: straight there.
            if panel.frame != frame { panel.setFrame(frame, display: true) }
            return
        }
        panel.setFrame(frame.offsetBy(dx: 0, dy: 12), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        model.hovered = nil
    }

    private func makePanel() -> NSPanel {
        // Over the snap preview (`SnapOverlay`, at .floating), so a zone stays in
        // sight while the preview below shows where the window will go.
        let panel = Panels.make(
            level: NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1),
            behavior: [.canJoinAllSpaces, .transient, .ignoresCycle],
            shadow: true,
            clickThrough: true
        )
        // Dark whatever the system appearance, like Windows' own bar: light
        // pictures on dark glass read at a glance over any window.
        panel.appearance = NSAppearance(named: .darkAqua)
        let hosting = NSHostingView(rootView: SnapLayoutBarView(model: model))
        hosting.sizingOptions = [] // `SnapLayoutBar.frame` decides the size, not SwiftUI
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }
}

/// The bar: a picture per suggestion and layout on a frosted plate. The zone under
/// the mouse takes the accent colour; a suggestion's taken zones show their app's icon.
struct SnapLayoutBarView: View {
    @ObservedObject var model: SnapLayoutBarModel

    var body: some View {
        let size: CGSize = SnapLayoutBar.size(count: model.tiles.count)
        ZStack(alignment: .topLeading) {
            ForEach(Array(model.tiles.indices), id: \.self) { (index: Int) in
                tile(index)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .frostedPanel(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true) // only ever under a dragging mouse; nothing to press
    }

    private func tile(_ index: Int) -> some View {
        let tile: SnapLayoutBar.Tile = model.tiles[index]
        let rect: CGRect = SnapLayoutBar.tileRect(index)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(tile.layout.zones.indices), id: \.self) { (zone: Int) in
                cell(tile.layout.zones[zone],
                     lit: model.hovered == SnapLayoutBar.Hit(tile: index, zone: zone),
                     icon: tile.filled[zone].flatMap { model.icons[$0] })
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
        .offset(x: rect.minX, y: rect.minY)
    }

    private func cell(_ zone: LayoutZone, lit: Bool, icon: NSImage?) -> some View {
        // Each zone gives up 1.5 pt on every side, so neighbours stand 3 pt apart.
        let rect: CGRect = SnapLayoutBar.rect(of: zone, in: SnapLayoutBar.tile).insetBy(dx: 1.5, dy: 1.5)
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let side: CGFloat = min(16, rect.width - 6, rect.height - 6)
        return shape
            .fill(lit ? Color(nsColor: .controlAccentColor) : Color.white.opacity(0.14))
            .overlay(shape.strokeBorder(Color.white.opacity(lit ? 0.55 : 0.22), lineWidth: 1))
            .overlay {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: side, height: side)
                }
            }
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
    }
}
