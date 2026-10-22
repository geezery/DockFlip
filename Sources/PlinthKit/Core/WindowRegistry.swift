import AppKit
import ApplicationServices

/// A window as Plinth sees it. Frames are in AX space (top-left origin).
public struct WindowSnapshot: Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let appName: String
    public let icon: NSImage?
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
}

/// Per-application Accessibility state.
@MainActor
final class TrackedApp {
    let app: NSRunningApplication
    let element: AXUIElement
    var observer: AXObserver?
    var windowElements: [CGWindowID: AXUIElement] = [:]
    weak var registry: WindowRegistry?

    var pid: pid_t { app.processIdentifier }

    init(app: NSRunningApplication, registry: WindowRegistry) {
        self.app = app
        self.element = AXUIElementCreateApplication(app.processIdentifier)
        self.registry = registry
    }

    func id(of element: AXUIElement) -> CGWindowID? {
        if let id = element.windowID, windowElements[id] != nil { return id }
        return windowElements.first { CFEqual($0.value, element) }?.key
    }
}

/// Keeps an event-driven list of standard windows and their most-recently-used order.
/// Nothing polls: state changes arrive as Accessibility and NSWorkspace notifications,
/// with a full reconcile only after wake, Space changes and display changes.
@MainActor
public final class WindowRegistry {
    private var apps: [pid_t: TrackedApp] = [:]
    private(set) var windows: [CGWindowID: WindowSnapshot] = [:]
    private(set) var mru = MRUList<CGWindowID>()
    private var tokens: [NSObjectProtocol] = []

    /// Called after any change. The taskbar (M2) redraws from this.
    public var onChange: (() -> Void)?

    public init() {}

    public func start() {
        // Never let an unresponsive app stall Plinth.
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)

        for app in NSWorkspace.shared.runningApplications where shouldTrack(app) {
            track(app)
        }
        seedMRUFromZOrder()
        observeWorkspace()
        onChange?()
    }

    // MARK: - Queries

    var trackedWindowCount: Int { windows.count }

    /// Windows for the ⌘Tab switcher in MRU order: windows on the current Space,
    /// plus minimized windows and windows of hidden apps.
    public func switcherWindows() -> [WindowSnapshot] {
        let onScreen = Set(Self.onScreenWindowIDs())
        return mru.items.compactMap { id -> WindowSnapshot? in
            guard var window = windows[id] else { return nil }
            window.isAppHidden = apps[window.pid]?.app.isHidden ?? false
            guard window.isMinimized || window.isAppHidden || onScreen.contains(id) else { return nil }
            return window
        }
    }

    // MARK: - Actions

    public func focus(_ id: CGWindowID) {
        guard let window = windows[id], let tracked = apps[window.pid],
              let element = tracked.windowElements[id] else { return }

        if tracked.app.isHidden { tracked.app.unhide() }
        if element.bool(kAXMinimizedAttribute) == true {
            element.set(kAXMinimizedAttribute, kCFBooleanFalse)
        }
        tracked.element.set(kAXFrontmostAttribute, kCFBooleanTrue)
        element.perform(kAXRaiseAction)
        element.set(kAXMainAttribute, kCFBooleanTrue)
        if !tracked.app.isActive {
            _ = tracked.app.activate(options: [])
        }

        mru.moveToFront(id)
        onChange?()
    }

    public func minimize(_ id: CGWindowID) {
        guard let window = windows[id], let element = apps[window.pid]?.windowElements[id] else { return }
        element.set(kAXMinimizedAttribute, kCFBooleanTrue)
    }

    public func close(_ id: CGWindowID) {
        guard let window = windows[id], let element = apps[window.pid]?.windowElements[id] else { return }
        element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction)
    }

    // MARK: - Tracking

    private func shouldTrack(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    private func track(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard apps[pid] == nil, !app.isTerminated else { return }

        let tracked = TrackedApp(app: app, registry: self)
        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success, let observer else {
            retryTrack(app, attempt: attempt)
            return
        }

        let refcon = Unmanaged.passUnretained(tracked).toOpaque()
        var subscribed = false
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            if AXObserverAddNotification(observer, tracked.element, name as CFString, refcon) == .success {
                subscribed = true
            }
        }
        // Freshly launched apps often refuse Accessibility for a moment.
        guard subscribed else {
            retryTrack(app, attempt: attempt)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        tracked.observer = observer
        apps[pid] = tracked
        refreshWindows(of: tracked)
    }

    private func retryTrack(_ app: NSRunningApplication, attempt: Int) {
        guard attempt < 5 else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
            self?.track(app, attempt: attempt + 1)
        }
    }

    private func untrack(pid: pid_t) {
        guard let tracked = apps.removeValue(forKey: pid) else { return }
        if let observer = tracked.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        for id in tracked.windowElements.keys {
            windows[id] = nil
            mru.remove(id)
        }
        onChange?()
    }

    private func observeWindow(_ element: AXUIElement, of tracked: TrackedApp) {
        guard let observer = tracked.observer else { return }
        let refcon = Unmanaged.passUnretained(tracked).toOpaque()
        for name in [
            kAXUIElementDestroyedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXTitleChangedNotification,
            kAXMovedNotification,
            kAXResizedNotification
        ] {
            _ = AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
    }

    /// Re-reads one app's windows from Accessibility and reconciles the model.
    private func refreshWindows(of tracked: TrackedApp) {
        var seen = Set<CGWindowID>()
        for element in tracked.element.elements(kAXWindowsAttribute) {
            guard element.isStandardWindow, let id = element.windowID else { continue }
            seen.insert(id)
            if tracked.windowElements[id] == nil {
                tracked.windowElements[id] = element
                observeWindow(element, of: tracked)
            }
            update(id: id, element: element, tracked: tracked)
            mru.appendIfMissing(id)
        }
        let gone = tracked.windowElements.keys.filter { !seen.contains($0) }
        for id in gone {
            tracked.windowElements[id] = nil
            windows[id] = nil
            mru.remove(id)
        }
        onChange?()
    }

    private func refreshAll() {
        for tracked in apps.values { refreshWindows(of: tracked) }
        // Pick up apps that launched while we were not looking (e.g. during sleep).
        for app in NSWorkspace.shared.runningApplications where shouldTrack(app) && apps[app.processIdentifier] == nil {
            track(app)
        }
    }

    private func update(id: CGWindowID, element: AXUIElement, tracked: TrackedApp) {
        let existing = windows[id]
        windows[id] = WindowSnapshot(
            id: id,
            pid: tracked.pid,
            appName: tracked.app.localizedName ?? "",
            icon: tracked.app.icon,
            title: element.string(kAXTitleAttribute) ?? existing?.title ?? "",
            frame: element.frame ?? existing?.frame ?? .zero,
            isMinimized: element.bool(kAXMinimizedAttribute) ?? existing?.isMinimized ?? false,
            isAppHidden: tracked.app.isHidden
        )
    }

    private func bringFocusedWindowToFront(of tracked: TrackedApp) {
        guard let focused = tracked.element.element(kAXFocusedWindowAttribute),
              let id = tracked.id(of: focused), windows[id] != nil else { return }
        mru.moveToFront(id)
        onChange?()
    }

    // MARK: - Accessibility notifications

    fileprivate func handle(_ notification: String, element: AXUIElement, tracked: TrackedApp) {
        switch notification {
        case kAXWindowCreatedNotification:
            // Subrole and title are often not set yet at creation time.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard let self, self.apps[tracked.pid] === tracked else { return }
                self.refreshWindows(of: tracked)
                if tracked.app.isActive { self.bringFocusedWindowToFront(of: tracked) }
            }

        case kAXUIElementDestroyedNotification:
            guard let id = tracked.id(of: element) else { return }
            tracked.windowElements[id] = nil
            windows[id] = nil
            mru.remove(id)
            onChange?()

        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if tracked.app.isActive { bringFocusedWindowToFront(of: tracked) }

        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
             kAXTitleChangedNotification, kAXMovedNotification, kAXResizedNotification:
            guard let id = tracked.id(of: element), let stored = tracked.windowElements[id] else { return }
            update(id: id, element: stored, tracked: tracked)
            onChange?()

        default:
            break
        }
    }

    // MARK: - Workspace notifications

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter

        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let launched = WindowRegistry.runningApp(from: note) else { return }
            MainActor.assumeIsolated {
                guard let self, self.shouldTrack(launched) else { return }
                self.track(launched)
            }
        })

        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let ended = WindowRegistry.runningApp(from: note) else { return }
            MainActor.assumeIsolated { self?.untrack(pid: ended.processIdentifier) }
        })

        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let active = WindowRegistry.runningApp(from: note) else { return }
            MainActor.assumeIsolated {
                guard let self, let tracked = self.apps[active.processIdentifier] else { return }
                self.bringFocusedWindowToFront(of: tracked)
            }
        })

        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let changed = WindowRegistry.runningApp(from: note) else { return }
                MainActor.assumeIsolated {
                    guard let self, let tracked = self.apps[changed.processIdentifier] else { return }
                    for (id, element) in tracked.windowElements {
                        self.update(id: id, element: element, tracked: tracked)
                    }
                    self.onChange?()
                }
            })
        }

        tokens.append(center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAll() }
        })

        tokens.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            // Window servers and apps settle a moment after wake.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(1))
                self?.refreshAll()
            }
        })

        tokens.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refreshAll()
            }
        })
    }

    private nonisolated static func runningApp(from note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    // MARK: - Window server

    /// Normal-layer windows currently on screen, front to back.
    static func onScreenWindowIDs() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            return CGWindowID(number.uint32Value)
        }
    }

    /// Initial MRU order follows the current stacking order; minimized windows go last.
    private func seedMRUFromZOrder() {
        let zOrder = Self.onScreenWindowIDs().filter { windows[$0] != nil }
        var ordered = MRUList(zOrder)
        for id in mru.items { ordered.appendIfMissing(id) }
        mru = ordered
    }
}

/// C callback for every AXObserver. Runs on the main run loop.
private func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracked = Unmanaged<TrackedApp>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        tracked.registry?.handle(name, element: element, tracked: tracked)
    }
}
