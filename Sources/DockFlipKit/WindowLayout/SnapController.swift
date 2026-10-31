import AppKit

/// Windows 11 window snapping: ⌃⌥ + arrows, ⌃⌥⇧ + ←/→, and dragging a window
/// to a screen edge or corner.
@MainActor
final class SnapController {
    private let registry: WindowRegistry
    /// Frames to return to when a snapped window is restored.
    private var restoreFrames: [CGWindowID: CGRect] = [:]
    private let overlay = SnapOverlay()
    private var monitors: [Any] = []
    private var drag: SnapDrag?
    private var dragZone: (region: SnapRegion, screen: NSScreen)?
    private var tilingHint = EdgeTilingHint()
    /// The earlier frame a snapped window took back when this drag pulled it off.
    private var unsnappedTo: CGRect?

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    func start() {
        guard monitors.isEmpty else { return }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDragged() }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    // MARK: - Keyboard

    func handle(_ key: SnapKey) -> Bool {
        Perf.shared.measure("snap.keyboard") { handleUnmeasured(key) }
    }

    private func handleUnmeasured(_ key: SnapKey) -> Bool {
        guard let (id, frame) = targetWindow() else { return false }
        let screens = DisplayLayout.screensLeftToRight()
        guard let display = DisplayLayout.screenIndex(for: frame, in: screens) else { return false }
        let area = DisplayLayout.usableArea(of: screens[display])
        let current = SnapEngine.region(matching: frame, in: area)

        switch SnapEngine.action(for: key, current: current, display: display, displayCount: screens.count) {
        case .snap(let region, let target):
            if current == nil { restoreFrames[id] = frame }
            registry.setFrame(of: id, to: SnapEngine.rect(for: region, in: DisplayLayout.usableArea(of: screens[target])))
        case .restore:
            restore(id, in: area)
        case .minimize:
            registry.minimize(id)
        case .none:
            break
        }
        return true
    }

    /// ⌃⌥⇧← / → : the same layout on the neighbouring display.
    func moveToDisplay(_ key: SnapKey) -> Bool {
        guard key == .left || key == .right, let (id, frame) = targetWindow() else { return false }
        let screens = DisplayLayout.screensLeftToRight()
        guard screens.count > 1, let display = DisplayLayout.screenIndex(for: frame, in: screens) else { return false }
        let target = key == .left ? display - 1 : display + 1
        guard screens.indices.contains(target) else { return true }

        let source = DisplayLayout.usableArea(of: screens[display])
        let destination = DisplayLayout.usableArea(of: screens[target])
        if let region = SnapEngine.region(matching: frame, in: source) {
            registry.setFrame(of: id, to: SnapEngine.rect(for: region, in: destination))
        } else {
            registry.setFrame(of: id, to: SnapEngine.translate(frame, from: source, to: destination))
        }
        return true
    }

    /// Puts the front window straight into `region` (from the menu bar menu).
    func snap(to region: SnapRegion) {
        guard let (id, frame) = targetWindow() else { return }
        let screens = DisplayLayout.screensLeftToRight()
        guard let display = DisplayLayout.screenIndex(for: frame, in: screens) else { return }
        let area = DisplayLayout.usableArea(of: screens[display])
        if SnapEngine.region(matching: frame, in: area) == nil { restoreFrames[id] = frame }
        registry.setFrame(of: id, to: SnapEngine.rect(for: region, in: area))
    }

    /// The front app's window and its frame, from the registry's memory: asking the
    /// app would hold up the key press for a second when the app hangs. Focus
    /// notifications keep the focused window first in the MRU order.
    private func targetWindow() -> (CGWindowID, CGRect)? {
        guard let id = registry.activeWindowID(),
              let frame = registry.knownFrame(of: id) else { return nil }
        return (id, frame)
    }

    private func restore(_ id: CGWindowID, in area: CGRect) {
        var target = restoreFrames.removeValue(forKey: id) ?? SnapEngine.defaultFreeFrame(in: area)
        if !target.intersects(area) {
            target = SnapEngine.defaultFreeFrame(in: area)
        }
        registry.setFrame(of: id, to: target)
    }

    // MARK: - Drag to edge

    /// Only remembers where the press was: every click on the Mac lands here, and
    /// `SnapDrag` looks the window up once the mouse has moved like a drag.
    private func mouseDown() {
        drag = SnapDrag(startMouse: NSEvent.mouseLocation)
        dragZone = nil
        unsnappedTo = nil
        tilingHint.newDrag()
    }

    private func mouseDragged() {
        guard var state = drag else { return }
        let mouse = NSEvent.mouseLocation

        state.moved(to: mouse, windowUnder: { point in
            Perf.shared.measure("snap.dragStart", quiet: true) { trackedWindow(under: point) }
        }, frame: { id in
            Perf.shared.measure("snap.dragCheck", quiet: true) { registry.knownFrame(of: id) }
        })
        let wasWindowDrag = drag?.window != nil
        drag = state
        guard let window = state.window else { return }
        if !wasWindowDrag { unsnapIfSnapped(window, mouse: mouse) }

        let zone = Self.zone(at: mouse)
        dragZone = zone
        if let zone {
            let area = DisplayLayout.usableArea(of: zone.screen)
            let rect = SnapEngine.rect(for: zone.region, in: area)
            let hint = tilingHint.showsHint(tilingOn: { NativeEdgeTiling.isOn })
                ? L("macOS edge tiling is on too. Turn it off in the DockFlip menu.")
                : nil
            overlay.show(Geometry.cocoaRect(fromAX: rect, primaryHeight: DisplayLayout.primaryHeight), hint: hint)
        } else {
            overlay.hide()
        }
    }

    private func mouseUp() {
        defer {
            drag = nil
            dragZone = nil
            unsnappedTo = nil
            overlay.hide()
        }
        guard let window = drag?.window, let zone = dragZone else { return }
        let startArea = DisplayLayout.screenIndex(for: window.startFrame, in: NSScreen.screens)
            .map { DisplayLayout.usableArea(of: NSScreen.screens[$0]) }
        if let unsnappedTo {
            // Dragged off one snap into another: ⌃⌥↓ still goes back to the free frame.
            restoreFrames[window.id] = unsnappedTo
        } else if let startArea, SnapEngine.region(matching: window.startFrame, in: startArea) == nil {
            restoreFrames[window.id] = window.startFrame
        }
        let rect = SnapEngine.rect(for: zone.region, in: DisplayLayout.usableArea(of: zone.screen))
        Log.snap.info("Drag snap to \(String(describing: zone.region), privacy: .public)")
        let id = window.id
        // Let the system finish its own drag handling first.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.registry.setFrame(of: id, to: rect)
        }
    }

    /// Windows gives a half- or quarter-snapped window its earlier size back as soon
    /// as it is dragged off, under the mouse. Called once, when the press becomes a
    /// window drag; only windows DockFlip snapped have a frame to go back to.
    private func unsnapIfSnapped(_ window: (id: CGWindowID, startFrame: CGRect), mouse: NSPoint) {
        guard let earlier = restoreFrames[window.id],
              let display = DisplayLayout.screenIndex(for: window.startFrame, in: NSScreen.screens),
              SnapEngine.region(matching: window.startFrame, in: DisplayLayout.usableArea(of: NSScreen.screens[display])) != nil
        else { return }
        // Where the window is now: it has followed the mouse since the press.
        let now = SnapDrag.startFrame(window.startFrame, at: self.drag?.startMouse ?? mouse, pressedAt: mouse)
        let axMouse = CGPoint(x: mouse.x, y: DisplayLayout.primaryHeight - mouse.y)
        restoreFrames.removeValue(forKey: window.id)
        unsnappedTo = earlier
        Log.snap.info("Drag unsnap to the earlier size")
        registry.setFrame(of: window.id, to: SnapEngine.unsnappedFrame(size: earlier.size, from: now, mouse: axMouse))
    }

    /// The tracked window under the mouse and its frame: one window-list read,
    /// and the frame from the registry's memory, which the moved notifications
    /// keep current through the drag. Its app is never asked.
    private func trackedWindow(under cocoaPoint: NSPoint) -> (id: CGWindowID, frame: CGRect)? {
        guard let id = windowID(under: cocoaPoint), let frame = registry.knownFrame(of: id) else { return nil }
        return (id, frame)
    }

    /// Topmost normal window under the mouse that DockFlip tracks.
    private func windowID(under cocoaPoint: NSPoint) -> CGWindowID? {
        let point = CGPoint(x: cocoaPoint.x, y: DisplayLayout.primaryHeight - cocoaPoint.y)
        guard let top = WindowServer.windows(onScreenOnly: true, visibleOnly: true).first(where: { $0.bounds.contains(point) }) else { return nil }
        return registry.window(top.id) != nil ? top.id : nil
    }

    /// The snap zone under the mouse (Cocoa coordinates), Windows 11 style:
    /// side edges give halves, the top edge maximizes, near a corner gives quarters.
    /// Edges shared with another display do not count.
    static func zone(at point: NSPoint) -> (region: SnapRegion, screen: NSScreen)? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }) else { return nil }
        let frame = screen.frame
        let edge: CGFloat = 3
        let corner: CGFloat = 80

        func onScreen(_ p: NSPoint) -> Bool {
            NSScreen.screens.contains { NSMouseInRect(p, $0.frame, false) }
        }

        let atLeft = point.x <= frame.minX + edge && !onScreen(NSPoint(x: frame.minX - 2, y: point.y))
        let atRight = point.x >= frame.maxX - edge - 1 && !onScreen(NSPoint(x: frame.maxX + 2, y: point.y))
        let atTop = point.y >= frame.maxY - edge - 1 && !onScreen(NSPoint(x: point.x, y: frame.maxY + 2))
        let nearTop = point.y >= frame.maxY - corner
        let nearBottom = point.y <= frame.minY + corner
        let nearLeft = point.x <= frame.minX + corner
        let nearRight = point.x >= frame.maxX - corner

        if atLeft { return (nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf, screen) }
        if atRight { return (nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf, screen) }
        if atTop { return (nearLeft ? .topLeft : nearRight ? .topRight : .maximized, screen) }
        return nil
    }
}
