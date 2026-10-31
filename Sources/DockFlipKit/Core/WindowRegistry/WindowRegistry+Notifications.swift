import AppKit
import ApplicationServices

@MainActor
extension WindowRegistry {
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
                tracked.bringFocusedForward = true
                self.refreshWindows(of: tracked)
            }

        case kAXUIElementDestroyedNotification:
            // A read on its way may still list the window: read once more after it.
            if tracked.isReading { tracked.readAgain = true }
            guard let id = tracked.id(of: element) else { return }
            tracked.windowElements[id] = nil
            windows[id] = nil
            mru.remove(id)
            notifyChange()

        case kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification:
            if tracked.app.isActive { bringFocusedWindowToFront(of: tracked) }

        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
             kAXTitleChangedNotification, kAXMovedNotification, kAXResizedNotification:
            // A read on its way may carry the state from before: read once more after it.
            if tracked.isReading { tracked.readAgain = true }
            guard let id = tracked.id(of: element), let stored = tracked.windowElements[id] else { return }
            update(id: id, element: stored, tracked: tracked)
            notifyChange()

        default:
            break
        }
    }

    // MARK: - Workspace notifications

    func observeWorkspace() {
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
                self.activePID = active.processIdentifier
                if let tracked = self.apps[active.processIdentifier] {
                    self.appActivated(tracked)
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
                    self.appHiddenOrShown(tracked)
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
}

/// C callback for every AXObserver. Runs on the main run loop.
func axObserverCallback(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let tracked = Unmanaged<TrackedApp>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        tracked.registry?.handle(name, element: element, tracked: tracked)
    }
}
