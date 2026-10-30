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
    func refreshWindows(of tracked: TrackedApp) {
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
        let inventory = WindowServer.inventory()[tracked.pid] ?? []
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
            let found = WindowServer.findWindows(pid: pid, ids: missing).mapValues { SendableElement(element: $0) }
            await self?.searchFinished(found, pid: pid, of: missing.count, name: name)
        }
    }

    private func searchFinished(_ found: [CGWindowID: SendableElement], pid: pid_t, of total: Int, name: String) {
        searchingElsewhere.remove(pid)
        adopt(found.mapValues(\.element), pid: pid)
        Log.registry.notice("\(name, privacy: .public): \(found.count, privacy: .public) of \(total, privacy: .public) windows found on other Spaces")
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

    func update(id: CGWindowID, element: AXUIElement, tracked: TrackedApp) {
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

    func bringFocusedWindowToFront(of tracked: TrackedApp) {
        guard let focused = tracked.element.element(kAXFocusedWindowAttribute),
              let id = tracked.id(of: focused), windows[id] != nil else { return }
        mru.moveToFront(id)
        notifyChange()
    }

    /// "file:///Users/x/Budget%202026.xlsx" → "Budget 2026.xlsx"
    private nonisolated static func documentName(_ value: String) -> String? {
        let url = URL(string: value) ?? URL(fileURLWithPath: value)
        let name = url.lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
