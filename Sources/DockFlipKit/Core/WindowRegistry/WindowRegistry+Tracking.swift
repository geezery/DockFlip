import AppKit
import ApplicationServices

@MainActor
extension WindowRegistry {
    // MARK: - Tracking

    func shouldTrack(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != ProcessInfo.processInfo.processIdentifier
    }

    func track(_ app: NSRunningApplication, attempt: Int = 0) {
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
            let subscriber = WindowSubscriber(observer: observer, refcon: Unmanaged.passUnretained(tracked).toOpaque())
            tracked.subscribeWindow = { subscriber.subscribe($0) }
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

    func untrack(pid: pid_t) {
        appOrder.removeAll { $0 == pid }
        unresponsive.remove(pid)
        searchedElsewhere[pid] = nil
        appQueues.forget(pid)
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

    /// Subscribes a newly seen window on the app's queue: each of its six
    /// registrations waits on the app (see `WindowSubscriber`).
    private func observeWindow(_ element: AXUIElement, of tracked: TrackedApp) {
        guard let subscribe = tracked.subscribeWindow else { return }
        let window = SendableElement(element: element)
        appQueues.run(for: tracked.pid, { subscribe(window) })
    }

    /// Re-reads one app's windows from Accessibility and reconciles the model.
    /// Returns before the app is asked: the reads run on the app's queue
    /// (`AppQueues`), and the model changes on the main actor once it answered.
    func refreshWindows(of tracked: TrackedApp) {
        // One read at a time per app. Asked again meanwhile (a window created, the
        // icon pointed at once more), it reads once more after this one.
        guard !tracked.isReading else {
            tracked.readAgain = true
            return
        }
        tracked.isReading = true
        let app = SendableElement(element: tracked.element)
        let read = tracked.readWindows
        let start = Perf.now()
        appQueues.run(for: tracked.pid, { read(app.element) }, then: { [weak self] result in
            tracked.isReading = false
            guard let self else { return }
            defer { self.launchReadFinished(tracked.pid) }
            guard self.apps[tracked.pid] === tracked else { return }
            Perf.shared.record("ax.refreshWindows", since: start, detail: tracked.app.localizedName ?? "")
            self.reconcile(result, of: tracked)
            if tracked.readAgain {
                tracked.readAgain = false
                self.refreshWindows(of: tracked)
            }
        })
    }

    private func reconcile(_ read: WindowsRead, of tracked: TrackedApp) {
        markResponsiveness(of: tracked, error: read.error)
        guard read.error != .cannotComplete else {
            // Busy or hung: keep what we know and ask again shortly. The retry reads
            // again, so a request made during this read needs no read of its own.
            tracked.readAgain = false
            scheduleRetry(of: tracked)
            return
        }
        let inventory = WindowServer.inventory()[tracked.pid] ?? []
        let plan = WindowsReconcile.after(
            listed: read.windows.map { (id: $0.id, isStandard: $0.isStandard) },
            known: Set(tracked.windowElements.keys),
            inventory: inventory
        )
        for window in read.windows where window.isStandard == true {
            if tracked.windowElements[window.id] == nil {
                tracked.windowElements[window.id] = window.element
                observeWindow(window.element, of: tracked)
            }
            update(id: window.id, with: window.attributes, tracked: tracked)
            mru.appendIfMissing(window.id)
        }
        for id in plan.gone {
            tracked.windowElements[id] = nil
            windows[id] = nil
            mru.remove(id)
        }
        if plan.readAgain {
            scheduleRetry(of: tracked)
        } else {
            tracked.retryCount = 0
        }
        if tracked.bringFocusedForward {
            tracked.bringFocusedForward = false
            bringFocusedWindowToFrontIfActive(of: tracked)
        }
        searchOtherSpaces(of: tracked, inventory: inventory)
        notifyChange()
    }

    /// The windows read at launch arrive app by app: each answer puts the windows
    /// known so far into stacking order, as `start()` would have done at once.
    private func launchReadFinished(_ pid: pid_t) {
        guard launchReads.remove(pid) != nil else { return }
        seedMRUFromZOrder()
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
            // Each found window's kind and state are read here too, off the main thread.
            let found = WindowServer.findWindows(pid: pid, ids: missing).map { WindowsRead.Window.read(id: $0.key, element: $0.value).window }
            await self?.searchFinished(found, pid: pid, of: missing.count, name: name)
        }
    }

    private func searchFinished(_ found: [WindowsRead.Window], pid: pid_t, of total: Int, name: String) {
        searchingElsewhere.remove(pid)
        adopt(found, pid: pid)
        Log.registry.notice("\(name, privacy: .public): \(found.count, privacy: .public) of \(total, privacy: .public) windows found on other Spaces")
    }

    private func adopt(_ found: [WindowsRead.Window], pid: pid_t) {
        guard let tracked = apps[pid], !found.isEmpty else { return }
        for window in found where tracked.windowElements[window.id] == nil && window.isStandard == true {
            tracked.windowElements[window.id] = window.element
            observeWindow(window.element, of: tracked)
            update(id: window.id, with: window.attributes, tracked: tracked)
            mru.appendIfMissing(window.id)
        }
        notifyChange()
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

    func refreshAll() {
        for tracked in apps.values { refreshWindows(of: tracked) }
        // Pick up apps that launched while we were not looking (e.g. during sleep).
        for app in NSWorkspace.shared.runningApplications where shouldTrack(app) && apps[app.processIdentifier] == nil {
            track(app)
        }
    }

    /// The app said a window moved, resized, was retitled or (de)miniaturized. Its
    /// state is read on the app's queue: an app that hangs right after (a long drag,
    /// a beachball while resizing) would hold up every click for 1 s on the main
    /// thread. One read at a time per window: a drag's hundreds of moves make one
    /// more read after the one on its way, not one each.
    func windowChanged(_ id: CGWindowID, of tracked: TrackedApp) {
        guard let element = tracked.windowElements[id] else { return }
        guard !tracked.updating.contains(id) else {
            tracked.updateAgain.insert(id)
            return
        }
        tracked.updating.insert(id)
        let window = SendableElement(element: element)
        let read = tracked.readWindow
        appQueues.run(for: tracked.pid, { read(id, window) }, then: { [weak self] answer in
            tracked.updating.remove(id)
            guard let self, self.apps[tracked.pid] === tracked else { return }
            // A window closed meanwhile stays gone.
            guard tracked.windowElements[id] != nil else {
                tracked.updateAgain.remove(id)
                return
            }
            self.update(id: id, with: answer.attributes, tracked: tracked)
            self.notifyChange()
            if tracked.updateAgain.remove(id) != nil {
                self.windowChanged(id, of: tracked)
            }
        })
    }

    /// What the app did not say keeps its last known value.
    func update(id: CGWindowID, with attributes: WindowAttributes, tracked: TrackedApp) {
        let existing = windows[id]
        windows[id] = WindowSnapshot(
            id: id,
            pid: tracked.pid,
            bundleID: tracked.app.bundleIdentifier,
            appName: tracked.app.localizedName ?? "",
            icon: tracked.app.icon,
            title: attributes.title ?? existing?.title ?? "",
            frame: attributes.frame ?? existing?.frame ?? .zero,
            isMinimized: attributes.isMinimized ?? existing?.isMinimized ?? false,
            isAppHidden: tracked.app.isHidden,
            document: attributes.document ?? existing?.document
        )
    }

    /// The app's focused window changed, or its windows were just read: if it is
    /// the active app, its focused window comes first once it says which, asked on
    /// its queue (an app can hang right after it notified).
    func bringFocusedWindowToFrontIfActive(of tracked: TrackedApp) {
        guard tracked.app.isActive else { return }
        // Active since before DockFlip started: no activation was seen to set it.
        if activePID == nil { activePID = tracked.pid }
        bringFocusedWindowToFrontLater(of: tracked)
    }

    private func moveToFront(_ focused: AXUIElement, of tracked: TrackedApp) {
        guard let id = tracked.id(of: focused), windows[id] != nil else { return }
        mru.moveToFront(id)
        notifyChange()
    }

    // MARK: - Activate, hide, unhide

    /// macOS activated the app. It brings a hung app forward without its help, so
    /// the app is asked on its own queue, never on the main thread.
    func appActivated(_ tracked: TrackedApp) {
        // Windows missed earlier because the app was busy: read them now.
        // Its focused window comes forward once they are read.
        if tracked.windowElements.isEmpty || tracked.observer == nil {
            tracked.retryCount = 0
            tracked.bringFocusedForward = true
            refreshWindows(of: tracked)
        } else {
            bringFocusedWindowToFrontLater(of: tracked)
        }
    }

    /// Asks for the focused window on the app's queue, and puts it first once the
    /// app answered, if it is still the active app.
    func bringFocusedWindowToFrontLater(of tracked: TrackedApp) {
        let app = SendableElement(element: tracked.element)
        let read = tracked.readFocusedWindow
        appQueues.run(for: tracked.pid, { read(app.element) }, then: { [weak self] focused in
            // Another app activated while this one answered late: its window stays first.
            guard let self, let focused, self.apps[tracked.pid] === tracked,
                  self.activePID == tracked.pid else { return }
            self.moveToFront(focused.element, of: tracked)
        })
    }

    /// The app was hidden or shown again (⌘H, Show Desktop). Whether it is hidden
    /// is the app's own flag, set at once; its windows' state is read on its queue,
    /// as a hung app is hidden too.
    func appHiddenOrShown(_ tracked: TrackedApp) {
        for id in tracked.windowElements.keys {
            windows[id]?.isAppHidden = tracked.app.isHidden
        }
        notifyChange()
        guard !tracked.windowElements.isEmpty else { return }
        let known = tracked.windowElements.mapValues { SendableElement(element: $0) }
        let read = tracked.readKnownWindows
        tracked.knownReadsOut += 1
        appQueues.run(for: tracked.pid, { read(known) }, then: { [weak self] answer in
            tracked.knownReadsOut -= 1
            let newer = tracked.framesNewerThanKnownRead
            if tracked.knownReadsOut == 0 { tracked.framesNewerThanKnownRead.removeAll() }
            guard let self, self.apps[tracked.pid] === tracked else { return }
            // A window closed meanwhile stays gone.
            for window in answer where tracked.windowElements[window.id] != nil {
                var attributes = window.attributes
                // A frame set while the app was read is newer than what it said.
                if newer.contains(window.id) { attributes.frame = nil }
                self.update(id: window.id, with: attributes, tracked: tracked)
            }
            self.notifyChange()
        })
    }
}
