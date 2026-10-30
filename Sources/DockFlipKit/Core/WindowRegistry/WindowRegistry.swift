import AppKit
import ApplicationServices

/// The heart of DockFlip: every standard window of every app, with title, frame and
/// state, in most-recently-used order. Every feature reads windows from here and
/// acts on them through here.
///
/// Event-driven, nothing polls:
/// - Accessibility notifications per app (window created, focused, destroyed,
///   minimized, moved, resized, retitled) keep each window current;
/// - NSWorkspace notifications (launch, quit, activate, hide, Space change, wake)
///   keep the app list current and trigger a full re-read where needed.
/// Observers (`addObserver`) are told after changes, at most once per run loop turn.
///
/// Accessibility lists only windows on the current Space; windows elsewhere are
/// found through the window server (`WindowServer`).
@MainActor
public final class WindowRegistry {
    var apps: [pid_t: TrackedApp] = [:]
    var appOrder: [pid_t] = []
    /// Window ids already looked for on other Spaces, per app, so each is searched once.
    var searchedElsewhere: [pid_t: Set<CGWindowID>] = [:]
    var searchingElsewhere = Set<pid_t>()
    /// Apps whose Accessibility calls time out — shown as "Not responding".
    var unresponsive = Set<pid_t>()
    var windows: [CGWindowID: WindowSnapshot] = [:]
    var mru = MRUList<CGWindowID>()
    var tokens: [NSObjectProtocol] = []
    /// Accessibility calls that wait on an app (actions, the hover probe, window reads) run
    /// here, off the main thread, so a hung app never stalls the event taps.
    let appQueues = AppQueues()
    /// Apps whose first windows read at launch has not answered yet.
    var launchReads = Set<pid_t>()
    /// Apps with a probe on its way, so hovering a hung app's icon asks it once.
    private var probing = Set<pid_t>()
    /// Counts focus requests: an app that answers late is not brought forward over a newer one.
    private var focusRequest = 0

    private var observers: [@MainActor () -> Void] = []
    private var changePending = false

    /// `handler` runs after changes, coalesced to at most once per run loop turn.
    func addObserver(_ handler: @escaping @MainActor () -> Void) {
        observers.append(handler)
    }

    func notifyChange() {
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
        // Never let an unresponsive app stall DockFlip for long — but give slow apps
        // time to answer: Chrome builds its accessibility tree on the first
        // request, and Office apps and Notes can take well over 0.3 s. One second,
        // as in AltTab and DockDoor; a timeout is retried, never taken as "no windows".
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)

        for app in NSWorkspace.shared.runningApplications where shouldTrack(app) {
            track(app)
        }
        // Their windows arrive as each app answers (`launchReadFinished`).
        launchReads = Set(apps.keys)
        seedMRUFromZOrder()
        observeWorkspace()
        notifyChange()
    }

    // MARK: - Queries

    var trackedWindowCount: Int { windows.count }

    /// Every tracked window's id, on any Space, without asking the window server.
    var trackedWindowIDs: Dictionary<CGWindowID, WindowSnapshot>.Keys { windows.keys }

    /// Every window in MRU order, for ⌘Tab and the Dock: windows on the current
    /// Space, minimized windows, windows of hidden apps, and windows on other
    /// Spaces — on a Mac, full-screen apps live in Spaces of their own, and a
    /// full-screen Chrome must not vanish from ⌘Tab.
    public func switcherWindows() -> [WindowSnapshot] {
        let onScreen = Set(WindowServer.onScreenIDs())
        let existing = Set(WindowServer.inventory().values.joined())
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

    /// Whether DockFlip knows a window of the app, from memory only: no
    /// Accessibility or window-server call, so the Dock's click tap can ask.
    func hasWindows(bundleID: String) -> Bool {
        windows.values.contains { $0.bundleID == bundleID }
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

    /// The frame the window last reported (AX space), from memory only: the moved
    /// and resized notifications keep it current, so snapping asks the app nothing.
    /// Nil for a minimized window or one whose frame was never read.
    func knownFrame(of id: CGWindowID) -> CGRect? {
        guard let window = windows[id], !window.isMinimized, !window.frame.isEmpty else { return nil }
        return window.frame
    }

    /// Moves and resizes a window (`FrameSetter`). Returns before the app is
    /// asked: the calls run on the app's queue, and where the window ended up
    /// comes back into the registry.
    func setFrame(of id: CGWindowID, to rect: CGRect) {
        guard let pid = windows[id]?.pid, let element = element(for: id) else { return }
        let target = SendableElement(element: element)
        let start = Perf.now()
        appQueues.run(for: pid, { FrameSetter.set(rect, on: target.element) }, then: { [weak self] answer in
            self?.frameSet(of: id, pid: pid, answer: answer, start: start)
        })
    }

    private func frameSet(of id: CGWindowID, pid: pid_t, answer: FrameSetter.Answer, start: UInt64) {
        guard let tracked = apps[pid] else { return }
        Perf.shared.record("ax.setFrame", since: start, detail: tracked.app.localizedName ?? "")
        markResponsiveness(of: tracked, error: answer.error)
        if let frame = answer.frame { remember(frame, of: id) }
    }

    /// Keeps a frame read off the main thread. The moved and resized notifications
    /// usually bring it too, but not from an app that sends none, and a second
    /// snap key pressed right after the first must see where the window went.
    func remember(_ frame: CGRect, of id: CGWindowID) {
        guard windows[id] != nil, windows[id]?.frame != frame else { return }
        windows[id]?.frame = frame
        notifyChange()
    }

    /// The Accessibility element of a window (for reading its tabs).
    func axElement(for id: CGWindowID) -> AXUIElement? {
        element(for: id)
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
        // One short call, off the main thread: a hung app answers only after the
        // timeout, and the mouse is on the Dock, about to click.
        guard probing.insert(pid).inserted else { return }
        let app = SendableElement(element: tracked.element)
        let name = tracked.app.localizedName ?? ""
        let start = Perf.now()
        appQueues.run(for: pid, { () -> AXError in
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(app.element, kAXFocusedWindowAttribute as CFString, &value)
        }, then: { [weak self] error in
            self?.probeAnswered(pid: pid, error: error, name: name, start: start)
        })
    }

    private func probeAnswered(pid: pid_t, error: AXError, name: String, start: UInt64) {
        probing.remove(pid)
        Perf.shared.record("ax.probe", ms: Double(Perf.now() - start) / 1_000_000, detail: name, quiet: true)
        guard let tracked = apps[pid] else { return }
        markResponsiveness(of: tracked, error: error)
    }

    func markResponsiveness(of tracked: TrackedApp, error: AXError) {
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
        let inventory = WindowServer.inventory()
        let onScreen = Set(WindowServer.onScreenIDs())
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
        focusRequest += 1
        let request = focusRequest
        let pid = tracked.pid
        if unresponsive.contains(pid), !tracked.app.isActive {
            // macOS brings a hung app forward without its help; waiting for its
            // timeouts first would bring it forward a second late.
            _ = tracked.app.activate(options: [])
        }
        // The app's calls run off the main thread, in order (`AppQueues`).
        let app = SendableElement(element: tracked.element)
        let target = SendableElement(element: element)
        let start = Perf.now()
        appQueues.run(for: pid, { () -> AXError in
            var minimized: CFTypeRef?
            let error = AXUIElementCopyAttributeValue(target.element, kAXMinimizedAttribute as CFString, &minimized)
            // No answer in time: the app is hung, and each further call would wait as long.
            guard error != .cannotComplete else { return error }
            if (minimized as? Bool) == true {
                target.element.set(kAXMinimizedAttribute, kCFBooleanFalse)
            }
            app.element.set(kAXFrontmostAttribute, kCFBooleanTrue)
            target.element.perform(kAXRaiseAction)
            target.element.set(kAXMainAttribute, kCFBooleanTrue)
            return error
        }, then: { [weak self] error in
            self?.focusAnswered(pid: pid, request: request, error: error, start: start)
        })

        mru.moveToFront(id)
        notifyChange()
    }

    /// The app answered a focus request's calls, or timed out on the first one.
    private func focusAnswered(pid: pid_t, request: Int, error: AXError, start: UInt64) {
        guard let tracked = apps[pid] else { return }
        Perf.shared.record("ax.focus", since: start, detail: tracked.app.localizedName ?? "")
        markResponsiveness(of: tracked, error: error)
        // Another window was asked for since: this app must not come over it.
        guard request == focusRequest, !tracked.app.isActive else { return }
        _ = tracked.app.activate(options: [])
    }

    public func minimize(_ id: CGWindowID) {
        guard let window = windows[id], let element = element(for: id) else { return }
        let target = SendableElement(element: element)
        appQueues.run(for: window.pid, { target.element.set(kAXMinimizedAttribute, kCFBooleanTrue) })
    }

    /// Presses the window's close button, so the app can ask to save first — and
    /// looks again shortly, to bring that question forward (`CloseFollowUp`).
    public func close(_ id: CGWindowID) {
        guard let pid = windows[id]?.pid, let element = element(for: id) else { return }
        // Two calls to the app: on its queue, so a hung app never holds up the list's click.
        let target = SendableElement(element: element)
        appQueues.run(for: pid, {
            target.element.element(kAXCloseButtonAttribute)?.perform(kAXPressAction) == true
        }, then: { [weak self] pressed in
            guard pressed else { return }
            self?.followUpClose(of: id, pid: pid, element: target, isLastLook: false)
        })
    }

    /// One-shot looks, never a repeating timer: a save sheet is there within a
    /// fraction of a second, and a busy app gets one more second. Each look asks
    /// the app on its queue.
    private func followUpClose(of id: CGWindowID, pid: pid_t, element: SendableElement, isLastLook: Bool) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: isLastLook ? .seconds(1) : .milliseconds(400))
            self?.appQueues.run(for: pid, { CloseFollowUp.read(element.element) }, then: { [weak self] read in
                self?.closeLooked(at: id, pid: pid, element: element, read: read, isLastLook: isLastLook)
            })
        }
    }

    private func closeLooked(at id: CGWindowID, pid: pid_t, element: SendableElement, read: CloseFollowUp.Read, isLastLook: Bool) {
        let check = CloseFollowUp.Check(isTracked: windows[id] != nil, read: read)
        switch CloseFollowUp.after(check, isLastLook: isLastLook) {
        case .done:
            break
        case .bringForward:
            let name = apps[pid]?.app.localizedName ?? "?"
            Log.registry.notice("Close: bringing forward a window that asks first: \(name, privacy: .public)")
            focus(id)
        case .lookAgain:
            followUpClose(of: id, pid: pid, element: element, isLastLook: true)
        }
    }
}
