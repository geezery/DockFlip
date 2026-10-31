import AppKit

extension WindowRegistry {
    /// Running Dock apps that DockFlip knows no window of, the frontmost first, then in launch order,
    /// for ⌘Tab's app cards when every window is closed.
    func windowlessApps() -> [SwitcherApp] {
        let withWindows = Set(windows.values.map(\.pid))
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let apps = NSWorkspace.shared.runningApplications.filter {
            shouldTrack($0) && !withWindows.contains($0.processIdentifier)
        }
        // The app in front first, as the one you are already in.
        let ordered = apps.filter { $0.processIdentifier == front } + apps.filter { $0.processIdentifier != front }
        return ordered.map { app in
            SwitcherApp(pid: app.processIdentifier, name: app.localizedName ?? "", icon: app.icon)
        }
    }

    /// Brings an app forward and asks it to reopen a window, as a click on its
    /// Dock icon does: opening a running app sends it the reopen event.
    func openApp(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        guard let url = app.bundleURL else {
            _ = app.activate(options: [])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            guard error != nil else { return }
            // Opening failed (the app moved?): bringing it forward is still something.
            Task { @MainActor in _ = NSRunningApplication(processIdentifier: pid)?.activate(options: []) }
        }
    }
}
