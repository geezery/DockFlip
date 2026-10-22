import AppKit
import ApplicationServices

/// Makes the real macOS Dock behave like the Windows 11 taskbar. The Dock itself
/// stays exactly as it is — folders, Trash, badges, drag and drop, settings.
///
/// - Hover: resting the mouse on an app's icon opens the list of its windows
///   (`WindowListPopup`).
/// - Click: clicking the front app's icon minimizes its window, clicking again
///   restores it; clicking another app brings its most recent window forward.
///   Apps without windows are left to the Dock (launch, reopen).
/// - ⌃⌥1…9 activates the n-th app in the Dock (Win+1…9).
///
/// How (DockDoor's approach): the Dock's Accessibility tree reports which icon the
/// mouse is on (`kAXSelectedChildrenChangedNotification` on its icon list); a mouse
/// event tap takes over clicks on icons of apps that have windows.
@MainActor
final class DockController: WindowListSource {
    private struct HoveredIcon {
        let bundleID: String
        /// Icon frame in screen (Cocoa) coordinates.
        let anchor: NSRect
    }

    private let registry: WindowRegistry
    private let popup: WindowListPopup
    private var dockApp: AXUIElement?
    private var dockList: AXUIElement?
    private var observer: AXObserver?
    private var tokens: [NSObjectProtocol] = []

    private var hovered: HoveredIcon?
    /// The icon the mouse just left, to reopen its list if the mouse comes straight back.
    private var lastHovered: HoveredIcon?
    /// The Dock's icon list on screen (Cocoa coordinates).
    private var dockFrame: NSRect?
    /// Mouse-move monitor, present only while the mouse is on the Dock or the list.
    private var mouseMonitor: Any?

    private var clickTap: CFMachPort?
    /// The mouse-down was taken over, so its mouse-up is too.
    private var swallowNextUp = false
    /// The Dock's icon list in AX coordinates, kept so a click anywhere on the
    /// screen is checked without asking the Dock (the tap must stay fast).
    private var dockListAXFrame: CGRect?
    /// The window an icon click minimized, restored by the next click on that icon.
    private var minimizedByClick: (bundleID: String, windowID: CGWindowID)?
    private(set) var dockEdge: DockEdge = .bottom

    init(registry: WindowRegistry) {
        self.registry = registry
        self.popup = WindowListPopup(registry: registry)
        popup.source = self
    }

    func start() {
        attach()
        installClickTap()
        // The Dock restarts after its settings change; follow it.
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self?.attach()
            }
        })
    }

    // MARK: - Watching the Dock

    /// Finds the Dock's icon list and subscribes to its "highlighted icon" changes.
    private func attach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        dockList = nil

        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            Log.app.error("Dock not running")
            return
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = app.elements(kAXChildrenAttribute).first(where: { $0.string(kAXRoleAttribute) == kAXListRole }) else {
            Log.app.error("Dock list not found")
            return
        }
        var newObserver: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, dockObserverCallback, &newObserver) == .success, let newObserver else {
            Log.app.error("Could not observe the Dock")
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = AXObserverAddNotification(newObserver, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard status == .success else {
            Log.app.error("Could not subscribe to Dock hover (\(status.rawValue, privacy: .public))")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        observer = newObserver
        dockApp = app
        dockList = list
        dockListAXFrame = list.frame
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        dockEdge = orientation == "left" ? .left : orientation == "right" ? .right : .bottom
        Log.app.notice("Attached to the Dock")
    }

    /// The Dock's highlighted icon changed: the mouse moved onto an icon or off the Dock.
    fileprivate func hoverChanged() {
        Perf.shared.measure("dock.hover", quiet: true) { hoverChangedUnmeasured() }
    }

    private func hoverChangedUnmeasured() {
        guard let list = dockList,
              let element = list.elements(kAXSelectedChildrenAttribute).first,
              let icon = Self.appIcon(element) else {
            hovered = nil
            popup.itemExited()
            return
        }
        hovered = icon
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: icon.bundleID).first {
            // Catches hung apps and windows missed earlier, while the user points at it.
            registry.probe(pid: app.processIdentifier)
        }
        popup.itemEntered(icon.bundleID)
        if let frame = list.frame {
            dockListAXFrame = frame
            dockFrame = Geometry.cocoaRect(fromAX: frame, primaryHeight: DisplayLayout.primaryHeight)
        }
        watchMouse()
    }

    /// The app behind a Dock icon, or nil for folders, the Trash and separators.
    private static func appIcon(_ element: AXUIElement) -> HoveredIcon? {
        guard element.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = element.copyAttribute(kAXURLAttribute) as? URL,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              let frame = element.frame else { return nil }
        return HoveredIcon(bundleID: bundleID, anchor: Geometry.cocoaRect(fromAX: frame, primaryHeight: DisplayLayout.primaryHeight))
    }

    // MARK: - Mouse leaving

    /// The Dock does not always report the mouse leaving it. Mouse-move events
    /// fill the gap — event-driven: macOS calls this only when the mouse moves, and
    /// the monitor exists only from the first hovered icon until the mouse leaves
    /// the Dock and the list.
    private func watchMouse() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
    }

    private func stopWatchingMouse() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        lastHovered = nil
    }

    private func mouseMoved() {
        let mouse = NSEvent.mouseLocation
        let onPopup = popup.visibleFrame?.insetBy(dx: -6, dy: -6).contains(mouse) ?? false
        if let hovered {
            if Self.zone(of: hovered, edge: dockEdge).contains(mouse) {
                // Back on the icon from the list: the list's own exit must not close it.
                popup.cancelHide()
            } else if !onPopup {
                lastHovered = hovered
                self.hovered = nil
                popup.itemExited()
            }
        } else if let last = lastHovered, last.anchor.contains(mouse) {
            // Back on the same icon: the Dock reports no change, so reopen here.
            hovered = last
            lastHovered = nil
            popup.itemEntered(last.bundleID)
        }
        let onDock = dockFrame?.insetBy(dx: -4, dy: -4).contains(mouse) ?? false
        if hovered == nil, !onDock, !onPopup {
            stopWatchingMouse()
        }
    }

    /// The icon, reaching towards the list so the way there counts as on the icon.
    private static func zone(of icon: HoveredIcon, edge: DockEdge) -> NSRect {
        let a = icon.anchor
        let bridge: NSRect
        switch edge {
        case .bottom: bridge = NSRect(x: a.minX, y: a.maxY, width: a.width, height: 14)
        case .left: bridge = NSRect(x: a.maxX, y: a.minY, width: 14, height: a.height)
        case .right: bridge = NSRect(x: a.minX - 14, y: a.minY, width: 14, height: a.height)
        }
        return a.insetBy(dx: -4, dy: -4).union(bridge)
    }

    // MARK: - WindowListSource

    func windowListItem(for bundleID: String) -> WindowListItem? {
        // All the app's windows, including full-screen ones and those on other desktops.
        let windows = registry.switcherWindows().filter { $0.bundleID == bundleID }
        // Running without windows (the Dock's dot, nothing open — common on a Mac):
        // no list, the Dock's own name label is enough.
        guard !windows.isEmpty else { return nil }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        return WindowListItem(
            bundleID: bundleID,
            name: app?.localizedName ?? windows[0].appName,
            windows: windows,
            isNotResponding: app.map { registry.unresponsive.contains($0.processIdentifier) } ?? false
        )
    }

    func anchor(for bundleID: String) -> NSRect? {
        guard let hovered, hovered.bundleID == bundleID else { return nil }
        return hovered.anchor
    }

    // MARK: - Clicks on Dock icons

    private func installClickTap() {
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.leftMouseDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.leftMouseUp.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockClickCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.app.error("Could not create the Dock click tap")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickTap = tap
    }

    /// Returns true when the click is taken over (and must not reach the Dock).
    /// Clicks with ⌘, ⌥, ⌃ or ⇧ always go to the Dock (Show in Finder, Hide Others …).
    fileprivate func click(type: CGEventType, location: CGPoint, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let clickTap { CGEvent.tapEnable(tap: clickTap, enable: true) }
            return false
        case .leftMouseUp:
            defer { swallowNextUp = false }
            return swallowNextUp
        case .leftMouseDown:
            // Cheap checks first: clicks outside the Dock pass straight through.
            guard let listFrame = dockListAXFrame, listFrame.contains(location),
                  flags.isDisjoint(with: [.maskCommand, .maskAlternate, .maskControl, .maskShift]) else { return false }
            let handled = Perf.shared.measure("dock.click") { handleIconClick(at: location) }
            swallowNextUp = handled
            return handled
        default:
            return false
        }
    }

    private func handleIconClick(at location: CGPoint) -> Bool {
        guard let dockApp else { return false }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockApp, Float(location.x), Float(location.y), &hit) == .success,
              let element = hit, let icon = Self.appIcon(element),
              let item = windowListItem(for: icon.bundleID) else { return false }
        popup.hideNow()
        activate(item)
        return true
    }

    /// The Windows taskbar click: the front app's active window minimizes, and
    /// the next click brings that same window back; otherwise the app's most
    /// recent window comes forward (restored if minimized).
    private func activate(_ item: WindowListItem) {
        if let last = minimizedByClick, last.bundleID == item.bundleID,
           let window = item.windows.first(where: { $0.id == last.windowID }), window.isMinimized {
            minimizedByClick = nil
            registry.focus(window.id)
        } else if let active = registry.activeWindowID(), item.windows.contains(where: { $0.id == active }) {
            registry.minimize(active)
            minimizedByClick = (item.bundleID, active)
        } else if let first = item.windows.first {
            minimizedByClick = nil
            registry.focus(first.id)
        }
    }

    /// ⌃⌥1…9: the n-th app in the Dock, as Win+1…9 on Windows.
    func activateItem(at index: Int) {
        guard let list = dockList else { return }
        let apps = list.elements(kAXChildrenAttribute).compactMap(Self.appIcon)
        guard apps.indices.contains(index) else { return }
        let bundleID = apps[index].bundleID
        if let item = windowListItem(for: bundleID) {
            activate(item)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}

/// AX callback for the Dock's icon list. Runs on the main run loop.
private func dockObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let controller = Unmanaged<DockController>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { controller.hoverChanged() }
}

/// Mouse tap callback. Runs on the main run loop.
private func dockClickCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<DockController>.fromOpaque(refcon).takeUnretainedValue()
    let location = event.location
    let flags = event.flags
    let swallow: Bool = MainActor.assumeIsolated { controller.click(type: type, location: location, flags: flags) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
