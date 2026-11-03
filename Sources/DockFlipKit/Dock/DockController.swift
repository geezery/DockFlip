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
/// event tap takes over clicks on icons of apps that have windows. Drags and
/// press-and-hold on those icons are passed on to the Dock (`DockPress`).
@MainActor
final class DockController: WindowListSource {
    struct HoveredIcon {
        let bundleID: String
        /// Icon frame in screen (Cocoa) coordinates.
        let anchor: NSRect
        /// The same frame in AX coordinates, as the click tap sees the mouse.
        let axFrame: CGRect
    }

    let registry: WindowRegistry
    let popup: WindowListPopup
    var dockApp: AXUIElement?
    var dockList: AXUIElement?
    private var observer: AXObserver?
    private var tokens: [NSObjectProtocol] = []

    var hovered: HoveredIcon?
    /// The icon the mouse just left, to reopen its list if the mouse comes straight back.
    private var lastHovered: HoveredIcon?
    /// The Dock's icon list on screen (Cocoa coordinates).
    private var dockFrame: NSRect?
    /// Mouse-move monitor, present only while the mouse is on the Dock or the list.
    private var mouseMonitor: Any?

    /// The icon whose list opened last, kept while the mouse crosses to the list.
    var listIcon: HoveredIcon?
    /// The mouse's recent positions, to tell a diagonal towards the list from a move
    /// to the next icon.
    var aim = DockAim()
    /// A neighbouring icon the Dock highlighted while the mouse was heading for the
    /// open list. It takes over only if the mouse rests on it or turns away.
    var pending: HoveredIcon?
    /// Where the mouse was when `pending` began: the tip of the aiming triangle.
    var pendingApex: CGPoint?
    /// The mouse's distance to the list at its closest so far while pending.
    var pendingDistance: CGFloat = 0
    var pendingTask: Task<Void, Never>?
    /// How long the mouse may rest on the neighbour before its list takes over: long
    /// enough for a hand slowing down near the list, short enough that pointing at
    /// the neighbour on purpose still feels immediate.
    static let aimGrace: Duration = .milliseconds(150)

    var clickTap: CFMachPort?
    var held: HeldPress?
    /// The Dock's icon list in AX coordinates, kept so a click anywhere on the
    /// screen is checked without asking the Dock (the tap must stay fast).
    var dockListAXFrame: CGRect?
    /// The window an icon click minimized, restored by the next click on that icon.
    var minimizedByClick: (bundleID: String, windowID: CGWindowID)?
    /// Bundle IDs of the Dock's apps by URL, for ⌃⌥1…9.
    var bundleIDs = BundleIDCache()
    private(set) var dockEdge: DockEdge = .bottom
    /// Tries a failed attach again a few times (login, Dock relaunch).
    private let attachRetry: DockAttachRetry

    init(registry: WindowRegistry) {
        self.registry = registry
        self.popup = WindowListPopup(registry: registry)
        self.attachRetry = DockAttachRetry()
        popup.source = self
    }

    func start() {
        attachWithRetries()
        installClickTap()
        // The Dock restarts after its settings change; follow it.
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == "com.apple.dock" else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self?.attachWithRetries()
            }
        })
    }

    // MARK: - Watching the Dock

    /// Attaches now and, when the Dock's tree is not ready yet (login, a Dock
    /// relaunch, a slow Mac), a few more times with one-shot waits (`DockAttachRetry`).
    private func attachWithRetries() {
        attachRetry.start { [weak self] in
            // Gone: nothing left to attach for, so the series ends.
            self?.attach() ?? true
        }
    }

    /// Finds the Dock's icon list and subscribes to its "highlighted icon" changes.
    /// Returns whether it attached; each failure is logged and recorded.
    @discardableResult
    private func attach() -> Bool {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        dockList = nil

        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            Log.app.error("Dock not running")
            SelfCheck.record { $0.recordDock(.failed("Dock not running")) }
            return false
        }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        guard let list = app.elements(kAXChildrenAttribute).first(where: { $0.string(kAXRoleAttribute) == kAXListRole }) else {
            Log.app.error("Dock list not found")
            SelfCheck.record { $0.recordDock(.failed("Dock list not found")) }
            return false
        }
        var newObserver: AXObserver?
        guard AXObserverCreate(dock.processIdentifier, dockObserverCallback, &newObserver) == .success, let newObserver else {
            Log.app.error("Could not observe the Dock")
            SelfCheck.record { $0.recordDock(.failed("could not observe the Dock")) }
            return false
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let status = AXObserverAddNotification(newObserver, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard status == .success else {
            Log.app.error("Could not subscribe to Dock hover (\(status.rawValue, privacy: .public))")
            SelfCheck.record { $0.recordDock(.failed("could not subscribe to Dock hover (error \(status.rawValue))")) }
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(newObserver), .commonModes)
        observer = newObserver
        dockApp = app
        dockList = list
        dockListAXFrame = list.frame
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, "com.apple.dock" as CFString) as? String
        dockEdge = orientation == "left" ? .left : orientation == "right" ? .right : .bottom
        SelfCheck.record { $0.recordDock(.attached) }
        Log.app.notice("Attached to the Dock")
        return true
    }

    /// The Dock's highlighted icon changed: the mouse moved onto an icon or off the Dock.
    fileprivate func hoverChanged() {
        // Counted for the self-check: an attached observer that never hears from
        // the Dock is a Dock whose Accessibility tree changed.
        SelfCheck.record { $0.dockHovers += 1 }
        Perf.shared.measure("dock.hover", quiet: true) { hoverChangedUnmeasured() }
    }

    private func hoverChangedUnmeasured() {
        guard let list = dockList,
              let element = list.elements(kAXSelectedChildrenAttribute).first,
              let icon = Self.appIcon(element) else {
            endAim()
            hovered = nil
            popup.itemExited()
            return
        }
        if deferIfAiming(at: icon) { return }
        endAim()
        enter(icon)
    }

    /// The mouse is on `icon`: it becomes the hovered icon and its list opens.
    func enter(_ icon: HoveredIcon) {
        hovered = icon
        listIcon = icon
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: icon.bundleID).first {
            // Catches hung apps and windows missed earlier, while the user points at it.
            registry.probe(pid: app.processIdentifier)
        }
        popup.itemEntered(icon.bundleID)
        if let frame = dockList?.frame {
            dockListAXFrame = frame
            dockFrame = Geometry.cocoaRect(fromAX: frame, primaryHeight: DisplayLayout.primaryHeight)
        }
        watchMouse()
    }

    /// The app behind a Dock icon, or nil for folders, the Trash and separators.
    static func appIcon(_ element: AXUIElement) -> HoveredIcon? {
        guard let bundleID = appBundleID(element), let frame = element.frame else { return nil }
        let anchor = Geometry.cocoaRect(fromAX: frame, primaryHeight: DisplayLayout.primaryHeight)
        return HoveredIcon(bundleID: bundleID, anchor: anchor, axFrame: frame)
    }

    /// The bundle ID behind a Dock icon, or nil for folders, the Trash and separators.
    static func appBundleID(_ element: AXUIElement) -> String? {
        guard element.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = element.copyAttribute(kAXURLAttribute) as? URL else { return nil }
        return Bundle(url: url)?.bundleIdentifier
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
        aim = DockAim()
    }

    private func mouseMoved() {
        let mouse = NSEvent.mouseLocation
        aim.moved(to: mouse)
        let onPopup = popup.visibleFrame?.insetBy(dx: -6, dy: -6).contains(mouse) ?? false
        if pending != nil {
            // On its way to the list over the neighbour: the list's icon stays hovered.
            followAim(mouse, onPopup: onPopup)
            return
        }
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
}

/// AX callback for the Dock's icon list. Runs on the main run loop.
private func dockObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let controller = Unmanaged<DockController>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { controller.hoverChanged() }
}
