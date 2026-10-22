import AppKit
import ApplicationServices

/// A window as Plinth sees it. Frames are in AX space (top-left origin).
public struct WindowSnapshot: Identifiable {
    public let id: CGWindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    public let icon: NSImage?
    public var title: String
    public var frame: CGRect
    public var isMinimized: Bool
    public var isAppHidden: Bool
    /// File name of the document shown in the window, when the app reports one.
    public var document: String?
    /// On another Space (another desktop, or a full-screen app). Set by `switcherWindows()`.
    public var isOnOtherSpace = false
}

/// Per-application Accessibility state.
@MainActor
final class TrackedApp {
    let app: NSRunningApplication
    let element: AXUIElement
    var observer: AXObserver?
    var windowElements: [CGWindowID: AXUIElement] = [:]
    weak var registry: WindowRegistry?
    /// A re-read is scheduled because the app did not answer in time.
    var retryPending = false
    var retryCount = 0

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
    private var appOrder: [pid_t] = []
    /// Window ids already looked for on other Spaces, per app, so each is searched once.
    private var searchedElsewhere: [pid_t: Set<CGWindowID>] = [:]
    private var searchingElsewhere = Set<pid_t>()
    /// Apps whose Accessibility calls time out — shown as "Not responding".
    private(set) var unresponsive = Set<pid_t>()
    private(set) var windows: [CGWindowID: WindowSnapshot] = [:]
    private(set) var mru = MRUList<CGWindowID>()
    private var tokens: [NSObjectProtocol] = []

    private var observers: [@MainActor () -> Void] = []
    private var changePending = false

    /// `handler` runs after changes, coalesced to at most once per run loop turn.
    func addObserver(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    private func notifyChange() {
        guard !changePending else { return }
        changePending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.changePending = false
            for observer in self.observers { observer() }
        }
    }

    public init() {}

    public func start() {
        // Never let an unresponsive app stall Plinth for long — but give slow apps
        // time to answer: Chrome builds its accessibility tree on the first
        // request, and Office apps and Notes can take well over 0.3 s. One second,
        // as in AltTab and DockDoor; a timeout is retried, never taken as "no windows".
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        for app in NSWorkspace.shared.runningApplications where shouldTrack(app) {
            track(app)
        }
        seedMRUFromZOrder()
        observeWorkspace()
        notifyChange()
    }

    // MARK: - Queries

    var trackedWindowCount: Int { windows.count }

    /// Every window in MRU order, for ⌘Tab and the Dock: windows on the current
    /// Space, minimized windows, windows of hidden apps, and windows on other
    /// Spaces — on a Mac, full-screen apps live in Spaces of their own, and a
    /// full-screen Chrome must not vanish from ⌘Tab.
    public func switcherWindows() -> [WindowSnapshot] {
        let onScreen = Set(Self.onScreenWindowIDs())
        let existing = Set(Self.windowInventory().values.joined())
        return mru.items.compactMap { id -> WindowSnapshot? in
            guard var window = windows[id] else { return nil }
            window.isAppHidden = apps[window.pid]?.app.isHidden ?? false
            window.isOnOtherSpace = !window.isMinimized && !window.isAppHidden && !onScreen.contains(id)
            // A window closed without telling us (apps tracked without notifications).
            if window.isOnOtherSpace && !existing.contains(id) { return nil }
            return window
        }
    }

    /// Windows on the current Space (plus minimized and hidden-app windows), in MRU order.
    func currentSpaceWindows() -> [WindowSnapshot] {
        switcherWindows().filter { !$0.isOnOtherSpace }
    }

    func window(_ id: CGWindowID) -> WindowSnapshot? {
        windows[id]
    }

    /// Bundle ids (or "pid:N" for apps without one) of tracked apps, in launch order.
    func runningApps() -> [NSRunningApplication] {
        appOrder.compactMap { apps[$0]?.app }
    }

    /// The focused window of the frontmost app, if Plinth tracks it.
    func focusedWindowID() -> CGWindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let tracked = apps[pid],
              let focused = tracked.element.element(kAXFocusedWindowAttribute) else { return nil }
        return tracked.id(of: focused)
    }

    /// The most recently used, not minimized window of the frontmost app.
    func activeWindowID() -> CGWindowID? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        return mru.items.first { id in
            guard let window = windows[id] else { return false }
            return window.pid == pid && !window.isMinimized
        }
    }

    /// Reads the frame straight from Accessibility (AX space).
    func liveFrame(of id: CGWindowID) -> CGRect? {
        element(for: id)?.frame
    }

    /// Moves and resizes a window. Size–position–size, because some apps clamp
    /// the size against the old position.
    func setFrame(of id: CGWindowID, to rect: CGRect) {
        guard let element = element(for: id) else { return }
        var origin = rect.origin
        var size = rect.size
        if let sizeValue = AXValueCreate(.cgSize, &size) { element.set(kAXSizeAttribute, sizeValue) }
        if let originValue = AXValueCreate(.cgPoint, &origin) { element.set(kAXPositionAttribute, originValue) }
        if let sizeValue = AXValueCreate(.cgSize, &size) { element.set(kAXSizeAttribute, sizeValue) }
    }

    private func element(for id: CGWindowID) -> AXUIElement? {
        guard let window = windows[id] else { return nil }
        return apps[window.pid]?.windowElements[id]
    }

    // MARK: - Actions

    public func focus(_ id: CGWindowID) {
        Perf.shared.measure("action.focus") { focusUnmeasured(id) }
    }

    /// Checks whether an app still answers (one short Accessibility call).
    /// Used when the user points at it, so a hung app is flagged without polling.
    func probe(pid: pid_t) {
        guard let tracked = apps[pid] else {
            // Not tracked yet (it refused Accessibility at launch): try now.
            if let app = NSRunningApplication(processIdentifier: pid), shouldTrack(app) { track(app) }
            return
        }
        // Windows missed earlier (the app was busy), or an app that sends no
        // notifications: read its windows now, while the user points at it.
        if tracked.windowElements.isEmpty || tracked.observer == nil {
            refreshWindows(of: tracked)
            return
        }
        var value: CFTypeRef?
        let error = Perf.shared.measure("ax.probe", detail: tracked.app.localizedName ?? "", quiet: true) {
            AXUIElementCopyAttributeValue(tracked.element, kAXFocusedWindowAttribute as CFString, &value)
        }
        markResponsiveness(of: tracked, error: error)
    }

    private func markResponsiveness(of tracked: TrackedApp, error: AXError) {
        let pid = tracked.pid
        let name = tracked.app.localizedName ?? "?"
        if error == .cannotComplete {
            if unresponsive.insert(pid).inserted {
                Log.registry.notice("Not responding: \(name, privacy: .public)")
                notifyChange()
            }
        } else if unresponsive.remove(pid) != nil {
            Log.registry.notice("Responding again: \(name, privacy: .public)")
            notifyChange()
        }
    }

    /// Lines for the debug log: tracked apps and window counts, never window titles.
    func debugSummary() -> [String] {
        var lines = ["apps=\(apps.count) windows=\(windows.count) unresponsive=\(unresponsive.count)"]
        let inventory = Self.windowInventory()
        let onScreen = Set(Self.onScreenWindowIDs())
        for pid in appOrder {
            guard let tracked = apps[pid] else { continue }
            let count = tracked.windowElements.count
            let minimized = tracked.windowElements.keys.filter { windows[$0]?.isMinimized == true }.count
            let elsewhere = tracked.windowElements.keys.filter { !onScreen.contains($0) && windows[$0]?.isMinimized == false }.count
            let flag = unresponsive.contains(pid) ? " NOT RESPONDING" : ""
            let observed = tracked.observer == nil ? " NO-AX-NOTIFICATIONS" : ""
            // windowServer: normal-layer windows the window server knows for the app, on all Spaces.
            lines.append("  \(tracked.app.localizedName ?? "?") [\(tracked.app.bundleIdentifier ?? "-")]: \(count) windows, \(minimized) minimized, \(elsewhere) other Space; windowServer=\(inventory[pid]?.count ?? 0)\(flag)\(observed)")
        }
        let untracked = NSWorkspace.shared.runningApplications.filter { shouldTrack($0) && apps[$0.processIdentifier] == nil }
        for app in untracked {
            lines.append("  NOT TRACKED: \(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "-")] windowServer=\(inventory[app.processIdentifier]?.count ?? 0)")
        }
        return lines
    }

    private func focusUnmeasured(_ id: CGWindowID) {
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
        notifyChange()
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
        Perf.shared.measure("ax.track", detail: app.localizedName ?? "") {
            trackUnmeasured(app, attempt: attempt)
        }
    }

    private func trackUnmeasured(_ app: NSRunningApplication, attempt: Int) {
        let pid = app.processIdentifier
        guard apps[pid] == nil, !app.isTerminated else { return }

        let tracked = TrackedApp(app: app, registry: self)
        let isLastAttempt = attempt >= Self.maxTrackAttempts
        var observer: AXObserver?
        let createStatus = AXObserverCreate(pid, axObserverCallback, &observer)
        var statuses: [Int32] = [createStatus.rawValue]
        var subscribed = false
        if createStatus == .success, let observer {
            let refcon = Unmanaged.passUnretained(tracked).toOpaque()
            for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
                let status = AXObserverAddNotification(observer, tracked.element, name as CFString, refcon)
                statuses.append(status.rawValue)
                if status == .success { subscribed = true }
            }
        }
        // Freshly launched apps often refuse Accessibility for a moment.
        guard subscribed || isLastAttempt else {
            if attempt == 0 {
                let name = app.localizedName ?? "?"
                let codes = statuses.map(String.init).joined(separator: ",")
                Log.registry.notice("\(name, privacy: .public) refused Accessibility notifications (\(codes, privacy: .public)); retrying")
            }
            retryTrack(app, attempt: attempt)
            return
        }

        if subscribed, let observer {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            tracked.observer = observer
        } else {
            // Some apps (seen with Microsoft Excel) never accept notifications. Track
            // them anyway: their windows are read when the app is activated, pointed
            // at in the Dock, or the Space changes.
            let name = app.localizedName ?? "?"
            let codes = statuses.map(String.init).joined(separator: ",")
            Log.registry.notice("\(name, privacy: .public) tracked without notifications (\(codes, privacy: .public))")
        }
        apps[pid] = tracked
        if !appOrder.contains(pid) { appOrder.append(pid) }
        refreshWindows(of: tracked)
    }

    private static let maxTrackAttempts = 6

    private func retryTrack(_ app: NSRunningApplication, attempt: Int) {
        guard attempt < Self.maxTrackAttempts else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
            self?.track(app, attempt: attempt + 1)
        }
    }

    private func untrack(pid: pid_t) {
        appOrder.removeAll { $0 == pid }
        unresponsive.remove(pid)
        searchedElsewhere[pid] = nil
        guard let tracked = apps.removeValue(forKey: pid) else { return }
        if let observer = tracked.observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        for id in tracked.windowElements.keys {
            windows[id] = nil
            mru.remove(id)
        }
        notifyChange()
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
        Perf.shared.measure("ax.refreshWindows", detail: tracked.app.localizedName ?? "") {
            refreshWindowsUnmeasured(of: tracked)
        }
    }

    private func refreshWindowsUnmeasured(of tracked: TrackedApp) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(tracked.element, kAXWindowsAttribute as CFString, &value)
        markResponsiveness(of: tracked, error: error)
        guard error != .cannotComplete else {
            // Busy or hung: keep what we know and ask again shortly.
            scheduleRetry(of: tracked)
            return
        }
        var seen = Set<CGWindowID>()
        var unanswered = false
        for element in (value as? [AXUIElement]) ?? [] {
            guard let id = element.windowID else { continue }
            let role = element.string(kAXRoleAttribute)
            let subrole = element.string(kAXSubroleAttribute)
            // A failed read is not an answer: a window whose role did not arrive in
            // time is kept if known, and read again shortly — never dropped.
            if role == nil || (role == kAXWindowRole && subrole == nil) {
                unanswered = true
                if tracked.windowElements[id] != nil { seen.insert(id) }
                continue
            }
            guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole else { continue }
            seen.insert(id)
            if tracked.windowElements[id] == nil {
                tracked.windowElements[id] = element
                observeWindow(element, of: tracked)
            }
            update(id: id, element: element, tracked: tracked)
            mru.appendIfMissing(id)
        }
        // Windows on other Spaces are missing from kAXWindows; the window server
        // still lists them. Only windows it no longer knows are gone.
        let inventory = Self.windowInventory()[tracked.pid] ?? []
        let gone = tracked.windowElements.keys.filter { !seen.contains($0) && !inventory.contains($0) }
        for id in gone {
            tracked.windowElements[id] = nil
            windows[id] = nil
            mru.remove(id)
        }
        if unanswered {
            scheduleRetry(of: tracked)
        } else {
            tracked.retryCount = 0
        }
        searchOtherSpaces(of: tracked, inventory: inventory)
        notifyChange()
    }

    /// Windows the window server knows but Accessibility did not list — windows on
    /// other Spaces and full-screen windows — are found by walking the app's
    /// Accessibility element ids (AltTab's technique). Runs off the main thread with
    /// a time budget; each window id is searched for once.
    private func searchOtherSpaces(of tracked: TrackedApp, inventory: Set<CGWindowID>) {
        let pid = tracked.pid
        let missing = inventory
            .subtracting(tracked.windowElements.keys)
            .subtracting(searchedElsewhere[pid] ?? [])
        guard !missing.isEmpty, !searchingElsewhere.contains(pid) else { return }
        searchingElsewhere.insert(pid)
        searchedElsewhere[pid, default: []].formUnion(missing)
        let name = tracked.app.localizedName ?? "?"
        Task.detached(priority: .utility) { [weak self] in
            let found = WindowRegistry.findWindows(pid: pid, ids: missing)
            await MainActor.run {
                guard let self else { return }
                self.searchingElsewhere.remove(pid)
                self.adopt(found, pid: pid)
                Log.registry.notice("\(name, privacy: .public): \(found.count, privacy: .public) of \(missing.count, privacy: .public) windows found on other Spaces")
            }
        }
    }

    private func adopt(_ found: [CGWindowID: AXUIElement], pid: pid_t) {
        guard let tracked = apps[pid], !found.isEmpty else { return }
        for (id, element) in found where tracked.windowElements[id] == nil {
            guard element.isStandardWindow else { continue }
            tracked.windowElements[id] = element
            observeWindow(element, of: tracked)
            update(id: id, element: element, tracked: tracked)
            mru.appendIfMissing(id)
        }
        notifyChange()
    }

    /// Walks Accessibility element ids of `pid` until every window in `ids` is
    /// found or the time budget runs out. Thread-safe; never call on the main thread.
    nonisolated static func findWindows(pid: pid_t, ids: Set<CGWindowID>, budget: TimeInterval = 0.3) -> [CGWindowID: AXUIElement] {
        guard let token = CFDataCreateMutable(kCFAllocatorDefault, 20) else { return [:] }
        CFDataSetLength(token, 20)
        guard let bytes = CFDataGetMutableBytePtr(token) else { return [:] }
        memset(bytes, 0, 20)
        var pidField = pid
        memcpy(bytes, &pidField, 4)
        var magic = Int32(0x636f636f)
        memcpy(bytes + 8, &magic, 4)

        var found: [CGWindowID: AXUIElement] = [:]
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var elementID: UInt64 = 0
        while found.count < ids.count, ProcessInfo.processInfo.systemUptime < deadline {
            memcpy(bytes + 12, &elementID, 8)
            elementID += 1
            guard let element = _AXUIElementCreateWithRemoteToken(token)?.takeRetainedValue() else { continue }
            var windowID: CGWindowID = 0
            guard _AXUIElementGetWindow(element, &windowID) == .success,
                  ids.contains(windowID), found[windowID] == nil else { continue }
            // Elements inside a window report the window's id too: keep the window itself.
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                  (role as? String) == kAXWindowRole else { continue }
            found[windowID] = element
        }
        return found
    }

    /// Reads an app's windows again after it failed to answer in time.
    private func scheduleRetry(of tracked: TrackedApp) {
        guard !tracked.retryPending, tracked.retryCount < 5 else { return }
        tracked.retryPending = true
        tracked.retryCount += 1
        let name = tracked.app.localizedName ?? "?"
        let attempt = tracked.retryCount
        Log.registry.notice("\(name, privacy: .public) did not answer in time; reading its windows again (attempt \(attempt, privacy: .public))")
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800 * attempt))
            tracked.retryPending = false
            guard let self, self.apps[tracked.pid] === tracked else { return }
            self.refreshWindows(of: tracked)
        }
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
            bundleID: tracked.app.bundleIdentifier,
            appName: tracked.app.localizedName ?? "",
            icon: tracked.app.icon,
            title: element.string(kAXTitleAttribute) ?? existing?.title ?? "",
            frame: element.frame ?? existing?.frame ?? .zero,
            isMinimized: element.bool(kAXMinimizedAttribute) ?? existing?.isMinimized ?? false,
            isAppHidden: tracked.app.isHidden,
            document: element.string(kAXDocumentAttribute).flatMap { Self.documentName($0) } ?? existing?.document
        )
    }

    private func bringFocusedWindowToFront(of tracked: TrackedApp) {
        guard let focused = tracked.element.element(kAXFocusedWindowAttribute),
              let id = tracked.id(of: focused), windows[id] != nil else { return }
        mru.moveToFront(id)
        notifyChange()
    }

    // MARK: - Accessibility notifications

    fileprivate func handle(_ notification: String, element: AXUIElement, tracked: TrackedApp) {
        Perf.shared.measure("ax.notification", detail: notification, quiet: true) {
            handleUnmeasured(notification, element: element, tracked: tracked)
        }
    }

    private func handleUnmeasured(_ notification: String, element: AXUIElement, tracked: TrackedApp) {
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
            notifyChange()

        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if tracked.app.isActive { bringFocusedWindowToFront(of: tracked) }

        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
             kAXTitleChangedNotification, kAXMovedNotification, kAXResizedNotification:
            guard let id = tracked.id(of: element), let stored = tracked.windowElements[id] else { return }
            update(id: id, element: stored, tracked: tracked)
            notifyChange()

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
                guard let self else { return }
                if let tracked = self.apps[active.processIdentifier] {
                    // Windows missed earlier because the app was busy: read them now.
                    if tracked.windowElements.isEmpty || tracked.observer == nil {
                        tracked.retryCount = 0
                        self.refreshWindows(of: tracked)
                    }
                    self.bringFocusedWindowToFront(of: tracked)
                } else if self.shouldTrack(active) {
                    // It refused Accessibility at launch; it answers now that it is in use.
                    self.track(active)
                }
                self.notifyChange()
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
                    self.notifyChange()
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

    /// "file:///Users/x/Budget%202026.xlsx" → "Budget 2026.xlsx"
    private nonisolated static func documentName(_ value: String) -> String? {
        let url = URL(string: value) ?? URL(fileURLWithPath: value)
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }

    private nonisolated static func runningApp(from note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    // MARK: - Window server

    /// Normal-layer windows of every app on every Space (plus minimized ones), by
    /// owner. Tiny helper windows are left out.
    static func windowInventory() -> [pid_t: Set<CGWindowID>] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var result: [pid_t: Set<CGWindowID>] = [:]
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 100, bounds.height >= 60 else { continue }
            result[pid_t(owner.int32Value), default: []].insert(CGWindowID(number.uint32Value))
        }
        return result
    }

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
