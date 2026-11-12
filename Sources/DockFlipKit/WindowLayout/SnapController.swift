import AppKit

/// Windows 11 window snapping: ⌃⌥ + arrows, ⌃⌥⇧ + ←/→, dragging a window to a
/// screen edge or corner, and the snap layouts bar at the top of the screen.
@MainActor
final class SnapController {
    let registry: WindowRegistry
    /// Frames to return to when a snapped window is restored.
    private var restoreFrames = SnapRestoreFrames()
    private let overlay = SnapOverlay()
    private var monitors: [Any] = []
    private var drag: SnapDrag?
    private var dragZone: DragTarget?
    private var tilingHint = EdgeTilingHint()
    /// The earlier frame a snapped window took back when this drag pulled it off.
    private var unsnappedTo: CGRect?
    /// The other windows offered for the region a snap leaves (Snap Assist).
    let assist = SnapAssistPanel()
    /// The layouts that come down at the top of a display during a window drag.
    let layoutBar = SnapLayoutBarPanel()
    var barTracking = SnapLayoutBar()


    init(registry: WindowRegistry) {
        self.registry = registry
        assist.onPick = { [weak self] id, region in self?.fill(region, with: id) }
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

    /// Accessibility was switched off: drag snapping and Snap Assist would show their
    /// overlay and cards but could move no window, so both stop until DockFlip restarts.
    func stop() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        assist.dismiss()
        drag = nil
        dragZone = nil
        unsnappedTo = nil
        overlay.hide()
        layoutBar.hide()
        barTracking.reset()
    }

    // MARK: - Keyboard

    func handle(_ key: SnapKey) -> Bool {
        Perf.shared.measure("snap.keyboard") { handleUnmeasured(key) }
    }

    private func handleUnmeasured(_ key: SnapKey) -> Bool {
        // The next snap closes the cards of the last one, as on Windows.
        assist.dismiss()
        guard let (id, frame) = targetWindow() else { return false }
        let screens = DisplayLayout.screensLeftToRight()
        guard let display = DisplayLayout.screenIndex(for: frame, in: screens) else { return false }
        let area = DisplayLayout.usableArea(of: screens[display])
        let current = SnapEngine.region(matching: frame, in: area)
        // A window in a layout zone the arrows have no name for (a third, two
        // thirds) is snapped all the same: ⌃⌥↓ gives its free frame back, as on Windows.
        let inLayoutZone = current == nil && SnapLayouts.zone(matching: frame, in: area) != nil
        if key == .down && inLayoutZone {
            restore(id, in: area)
            return true
        }

        switch SnapEngine.action(for: key, current: current, display: display, displayCount: screens.count) {
        case .snap(let region, let target):
            if current == nil && !inLayoutZone { remember(frame, for: id) }
            let targetArea = DisplayLayout.usableArea(of: screens[target])
            registry.setFrame(of: id, to: SnapEngine.rect(for: region, in: targetArea))
            offerAssist(after: region, of: id, in: targetArea)
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
        assist.dismiss()
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
        assist.dismiss()
        guard let (id, frame) = targetWindow() else { return }
        let screens = DisplayLayout.screensLeftToRight()
        guard let display = DisplayLayout.screenIndex(for: frame, in: screens) else { return }
        let area = DisplayLayout.usableArea(of: screens[display])
        if !Self.isSnapped(frame, in: area) { remember(frame, for: id) }
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
        var target = restoreFrames.take(id) ?? SnapEngine.defaultFreeFrame(in: area)
        if !target.intersects(area) {
            target = SnapEngine.defaultFreeFrame(in: area)
        }
        registry.setFrame(of: id, to: target)
    }

    /// Whether `frame` fills a snap region or a zone of a snap layout in `area`:
    /// such a frame is a snap, not a free frame to come back to.
    static func isSnapped(_ frame: CGRect, in area: CGRect) -> Bool {
        SnapEngine.region(matching: frame, in: area) != nil || SnapLayouts.zone(matching: frame, in: area) != nil
    }

    /// Keeps `frame` for ⌃⌥↓, dropping closed windows' frames as it goes.
    func remember(_ frame: CGRect, for id: CGWindowID) {
        restoreFrames.remember(frame, for: id, live: registry.trackedWindowIDs)
    }

    // MARK: - Snap Assist

    /// Offers the other windows for the region a snap to `region` leaves in `area`,
    /// if it leaves one and there are windows to offer.
    private func offerAssist(after region: SnapRegion, of id: CGWindowID, in area: CGRect) {
        guard let left = SnapAssist.remainingRegion(after: region) else { return }
        let rect = SnapEngine.rect(for: left, in: area)
        guard let offer = SnapAssist.offer(after: region, snappedID: id, windows: registry.switcherWindows(),
                                           limit: SnapAssistPanel.capacity(for: rect)) else { return }
        assist.show(offer.windows, over: rect)
    }

    /// The window picked in Snap Assist fills the region left: brought forward
    /// first (a minimized one comes back), then sized, both in order on its app's
    /// queue. Like any snap, ⌃⌥↓ gives a free window its frame back later.
    private func fill(_ region: CGRect, with id: CGWindowID) {
        if let frame = registry.knownFrame(of: id),
           let display = DisplayLayout.screenIndex(for: frame, in: NSScreen.screens),
           !Self.isSnapped(frame, in: DisplayLayout.usableArea(of: NSScreen.screens[display])) {
            remember(frame, for: id)
        }
        Log.snap.info("Snap Assist fills the region left")
        registry.focus(id)
        registry.setFrame(of: id, to: region)
    }

    // MARK: - Drag to edge

    /// Only remembers where the press was: every click on the Mac lands here, and
    /// `SnapDrag` looks the window up once the mouse has moved like a drag.
    private func mouseDown() {
        // A click anywhere but on the cards closes them; clicks on DockFlip's
        // own panel never reach this global monitor. Memory only, no window reads.
        assist.dismiss()
        drag = SnapDrag(startMouse: NSEvent.mouseLocation)
        dragZone = nil
        unsnappedTo = nil
        barTracking.reset()
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
        if !wasWindowDrag {
            unsnapIfSnapped(window, mouse: mouse)
            prepareLayoutBar(for: window.id)
        }

        let target = dragTarget(at: mouse, startMouse: state.startMouse)
        dragZone = target
        if let target {
            let rect = target.rect
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
            layoutBar.hide()
            barTracking.reset()
        }
        guard let window = drag?.window, let target = dragZone else { return }
        let startArea = DisplayLayout.screenIndex(for: window.startFrame, in: NSScreen.screens)
            .map { DisplayLayout.usableArea(of: NSScreen.screens[$0]) }
        if let unsnappedTo {
            // Dragged off one snap into another: ⌃⌥↓ still goes back to the free frame.
            remember(unsnappedTo, for: window.id)
        } else if let startArea, !Self.isSnapped(window.startFrame, in: startArea) {
            remember(window.startFrame, for: window.id)
        }
        if !target.others.isEmpty {
            Log.snap.info("Drag snap to a suggestion with \(target.others.count, privacy: .public) more windows")
        } else if let layout = target.layout {
            Log.snap.info("Drag snap to a layout of \(layout.layout.zones.count, privacy: .public) zones, zone \(layout.zone, privacy: .public)")
        } else if let region = target.region {
            Log.snap.info("Drag snap to \(String(describing: region), privacy: .public)")
        }
        let id = window.id
        let rect = target.rect
        let area = target.area
        let region = target.region
        let layout = target.layout
        let others = target.others
        // Let the system finish its own drag handling first.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            guard let self else { return }
            self.registry.setFrame(of: id, to: rect)
            if !others.isEmpty {
                self.arrange(others, around: id)
                return
            }
            // A click since the drop has moved on; the cards would come too late.
            guard self.drag == nil else { return }
            if let layout {
                self.offerAssist(after: layout.zone, of: layout.layout, of: id, in: area)
            } else if let region {
                self.offerAssist(after: region, of: id, in: area)
            }
        }
    }

    /// Windows gives a half- or quarter-snapped window its earlier size back as soon
    /// as it is dragged off, under the mouse. Called once, when the press becomes a
    /// window drag; only windows DockFlip snapped have a frame to go back to.
    private func unsnapIfSnapped(_ window: (id: CGWindowID, startFrame: CGRect), mouse: NSPoint) {
        guard let earlier = restoreFrames[window.id],
              let display = DisplayLayout.screenIndex(for: window.startFrame, in: NSScreen.screens),
              Self.isSnapped(window.startFrame, in: DisplayLayout.usableArea(of: NSScreen.screens[display]))
        else { return }
        // Where the window is now: it has followed the mouse since the press.
        let now = SnapDrag.startFrame(window.startFrame, at: self.drag?.startMouse ?? mouse, pressedAt: mouse)
        let axMouse = CGPoint(x: mouse.x, y: DisplayLayout.primaryHeight - mouse.y)
        restoreFrames.take(window.id)
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

    /// The snap zone under the mouse (Cocoa coordinates); the rule is `SnapZone`.
    static func zone(at point: NSPoint) -> (region: SnapRegion, screen: NSScreen)? {
        let screens = NSScreen.screens
        guard let zone = SnapZone.zone(at: point, screens: screens.map(\.frame)) else { return nil }
        return (zone.region, screens[zone.screen])
    }
}
