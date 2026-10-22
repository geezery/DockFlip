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
    private var drag: DragState?

    private struct DragState {
        let windowID: CGWindowID
        let startFrame: CGRect
        let startMouse: NSPoint
        var isWindowDrag = false
        var decided = false
        var zone: (region: SnapRegion, screen: NSScreen)?
    }

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

    private func targetWindow() -> (CGWindowID, CGRect)? {
        guard let id = registry.focusedWindowID() ?? registry.activeWindowID(),
              registry.window(id)?.isMinimized == false,
              let frame = registry.liveFrame(of: id) else { return nil }
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

    private func mouseDown() {
        let mouse = NSEvent.mouseLocation
        guard let id = windowID(under: mouse), let frame = registry.liveFrame(of: id) else {
            drag = nil
            return
        }
        drag = DragState(windowID: id, startFrame: frame, startMouse: mouse)
    }

    private func mouseDragged() {
        guard var state = drag else { return }
        let mouse = NSEvent.mouseLocation

        if !state.decided {
            let distance = hypot(mouse.x - state.startMouse.x, mouse.y - state.startMouse.y)
            guard distance > 8 else { return }
            if let frame = registry.liveFrame(of: state.windowID) {
                let moved = abs(frame.minX - state.startFrame.minX) + abs(frame.minY - state.startFrame.minY) > 4
                let resized = abs(frame.width - state.startFrame.width) + abs(frame.height - state.startFrame.height) > 2
                if moved && !resized {
                    state.isWindowDrag = true
                    state.decided = true
                } else if resized || distance > 60 {
                    state.decided = true
                }
            }
            drag = state
            guard state.isWindowDrag else { return }
        }
        guard state.isWindowDrag else { return }

        let zone = Self.zone(at: mouse)
        state.zone = zone
        drag = state
        if let zone {
            let area = DisplayLayout.usableArea(of: zone.screen)
            let rect = SnapEngine.rect(for: zone.region, in: area)
            overlay.show(Geometry.cocoaRect(fromAX: rect, primaryHeight: DisplayLayout.primaryHeight))
        } else {
            overlay.hide()
        }
    }

    private func mouseUp() {
        defer {
            drag = nil
            overlay.hide()
        }
        guard let state = drag, state.isWindowDrag, let zone = state.zone else { return }
        let startArea = DisplayLayout.screenIndex(for: state.startFrame, in: NSScreen.screens)
            .map { DisplayLayout.usableArea(of: NSScreen.screens[$0]) }
        if let startArea, SnapEngine.region(matching: state.startFrame, in: startArea) == nil {
            restoreFrames[state.windowID] = state.startFrame
        }
        let rect = SnapEngine.rect(for: zone.region, in: DisplayLayout.usableArea(of: zone.screen))
        Log.snap.info("Drag snap to \(String(describing: zone.region), privacy: .public)")
        let id = state.windowID
        // Let the system finish its own drag handling first.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(40))
            self?.registry.setFrame(of: id, to: rect)
        }
    }

    /// Topmost normal window under the mouse that Plinth tracks.
    private func windowID(under cocoaPoint: NSPoint) -> CGWindowID? {
        let point = CGPoint(x: cocoaPoint.x, y: DisplayLayout.primaryHeight - cocoaPoint.y)
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.contains(point) else { continue }
            let id = CGWindowID(number.uint32Value)
            return registry.window(id) != nil ? id : nil
        }
        return nil
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

/// The translucent "the window will go here" preview shown while dragging.
@MainActor
final class SnapOverlay {
    private var panel: NSPanel?

    func show(_ rect: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let inset = rect.insetBy(dx: 6, dy: 6)
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(inset, display: true)
            }
        } else {
            panel.setFrame(inset, display: true)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        view.layer?.borderWidth = 2
        panel.contentView = view
        return panel
    }
}
