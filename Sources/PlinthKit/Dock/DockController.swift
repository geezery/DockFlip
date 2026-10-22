import AppKit
import ApplicationServices

/// Dock mode (the default): the real macOS Dock stays exactly as it is — folders,
/// Trash, badges, drag and drop, sizes — and Plinth adds the Windows taskbar
/// behaviour to it:
/// - resting the mouse on an app's icon opens the list (or thumbnails) of its windows;
/// - clicking the icon of the app in front minimizes its window, clicking again
///   restores it, and clicking another app brings its most recent window forward.
///
/// Same approach as DockDoor: the Dock's Accessibility tree tells which icon the
/// mouse is on (`kAXSelectedChildrenChangedNotification` on the Dock's list), and a
/// mouse event tap takes over clicks on icons of apps that have windows.
@MainActor
final class DockController: PopupSource {
    private struct HoveredIcon {
        let key: String
        let bundleID: String
        /// Icon frame in screen (Cocoa) coordinates.
        let anchor: NSRect
    }

    private let registry: WindowRegistry
    private let popup: TaskbarPopup
    private var observer: AXObserver?
    private var dockApp: AXUIElement?
    private var dockList: AXUIElement?
    private var hovered: HoveredIcon?
    private var clickTap: CFMachPort?
    /// The mouse-down was taken over, so its mouse-up is too.
    private var swallowNextUp = false
    private var tokens: [NSObjectProtocol] = []

    init(registry: WindowRegistry) {
        self.registry = registry
        self.popup = TaskbarPopup(registry: registry)
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
        registry.addObserver { [weak self] in self?.popup.refreshIfVisible() }
    }

    // MARK: - Watching the Dock

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
        Log.app.notice("Dock mode attached to the Dock")
    }

    /// The Dock's highlighted icon changed: the mouse moved onto an icon or left the Dock.
    fileprivate func hoverChanged() {
        Perf.shared.measure("dock.hover", quiet: true) { hoverChangedUnmeasured() }
    }

    private func hoverChangedUnmeasured() {
        guard let list = dockList,
              let icon = list.elements(kAXSelectedChildrenAttribute).first,
              let hovered = Self.appIcon(icon) else {
            hovered = nil
            popup.itemExited()
            return
        }
        self.hovered = hovered
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: hovered.bundleID).first {
            registry.probe(pid: app.processIdentifier)
        }
        popup.itemEntered(hovered.key, on: 0)
    }

    /// The app behind a Dock icon, or nil for folders, the Trash and separators.
    private static func appIcon(_ element: AXUIElement) -> HoveredIcon? {
        guard element.string(kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = element.copyAttribute(kAXURLAttribute) as? URL,
              let bundleID = Bundle(url: url)?.bundleIdentifier,
              let frame = element.frame else { return nil }
        let anchor = Geometry.cocoaRect(fromAX: frame, primaryHeight: DisplayLayout.primaryHeight)
        return HoveredIcon(key: bundleID, bundleID: bundleID, anchor: anchor)
    }

    // MARK: - PopupSource

    func item(_ itemID: String, on displayID: CGDirectDisplayID) -> TaskbarItem? {
        // All the app's windows, including full-screen ones and those on other desktops.
        let windows = registry.switcherWindows().filter { $0.bundleID == itemID }
        // Running without windows (the Dock's dot, but nothing open — common on a Mac):
        // no popup, the Dock's own name label is enough.
        guard !windows.isEmpty else { return nil }
        let app = NSRunningApplication.runningApplications(withBundleIdentifier: itemID).first
        let active = registry.activeWindowID()
        let name = app?.localizedName ?? windows.first?.appName ?? itemID
        return TaskbarItem(
            id: itemID,
            appKey: itemID,
            bundleID: itemID,
            pid: app?.processIdentifier,
            name: name,
            icon: app?.icon ?? windows.first?.icon,
            label: nil,
            windowIDs: windows.map(\.id),
            isRunning: app != nil,
            isActive: active.map { id in windows.contains { $0.id == id } } ?? false,
            badge: nil,
            isNotResponding: app.map { registry.unresponsive.contains($0.processIdentifier) } ?? false
        )
    }

    func anchorRect(for itemID: String, on displayID: CGDirectDisplayID) -> NSRect? {
        guard let hovered, hovered.key == itemID else { return nil }
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
    fileprivate func click(type: CGEventType, location: CGPoint) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let clickTap { CGEvent.tapEnable(tap: clickTap, enable: true) }
            return false
        case .leftMouseUp:
            defer { swallowNextUp = false }
            return swallowNextUp
        case .leftMouseDown:
            guard let list = dockList, let listFrame = list.frame, listFrame.contains(location) else { return false }
            let handled = Perf.shared.measure("dock.click") { handleIconClick(at: location) }
            swallowNextUp = handled
            return handled
        default:
            return false
        }
    }

    /// Windows taskbar click: front app → minimize its window; otherwise bring the
    /// app's most recent window forward (restoring it if minimized). Apps without
    /// windows on this Space are left to the Dock (launch, reopen).
    private func handleIconClick(at location: CGPoint) -> Bool {
        guard let dockApp else { return false }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockApp, Float(location.x), Float(location.y), &hit) == .success,
              let element = hit, let icon = Self.appIcon(element),
              let item = item(icon.key, on: 0), let first = item.windowIDs.first else { return false }
        popup.hideNow()
        activate(item, firstWindow: first)
        return true
    }

    private func activate(_ item: TaskbarItem, firstWindow: CGWindowID) {
        if item.isActive, let active = registry.activeWindowID(), item.windowIDs.contains(active) {
            registry.minimize(active)
        } else {
            registry.focus(firstWindow)
        }
    }

    /// ⌃⌥1…9: the n-th app in the Dock, as Win+1…9 on Windows.
    func activateItem(at index: Int) -> Bool {
        guard let list = dockList else { return false }
        let apps = list.elements(kAXChildrenAttribute).compactMap(Self.appIcon)
        guard apps.indices.contains(index) else { return false }
        let bundleID = apps[index].bundleID
        if let item = item(bundleID, on: 0), let first = item.windowIDs.first {
            activate(item, firstWindow: first)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        return true
    }
}

/// AX callback for the Dock's list. Runs on the main run loop.
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
    let swallow: Bool = MainActor.assumeIsolated { controller.click(type: type, location: location) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
