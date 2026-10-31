import AppKit

/// Windows' "Show desktop" (Win+D, here ⌃⌥D): hides every app; pressing it
/// again brings back the ones it hid, and the window you were in gets the
/// keyboard back, as Win+D gives back the foreground window.
@MainActor
enum ShowDesktop {
    private static var hiddenApps: [NSRunningApplication] = []
    /// The app and window in front when the desktop was shown.
    private static var front: ShowDesktopFront?

    static func toggle(registry: WindowRegistry) {
        let stillHidden = hiddenApps.filter { !$0.isTerminated && $0.isHidden }
        if !stillHidden.isEmpty {
            for app in stillHidden { app.unhide() }
            let target = ShowDesktopFront.toRestore(front, unhidden: stillHidden.map(\.processIdentifier))
            hiddenApps = []
            front = nil
            if let target { giveBackKeyboard(to: target, registry: registry) }
            return
        }
        let own = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != own {
            front = ShowDesktopFront(pid: app.processIdentifier, windowID: registry.activeWindowID())
        } else {
            front = nil
        }
        hiddenApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != own && app.hide()
        }
    }

    /// Unhiding brings the apps back in whatever order macOS picks: put the window
    /// that was in front back on top, with the keyboard.
    private static func giveBackKeyboard(to target: ShowDesktopFront, registry: WindowRegistry) {
        if let id = target.windowID, registry.window(id) != nil {
            registry.focus(id)
        } else {
            _ = NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
        }
    }
}

/// The app (and its window) in front when ⌃⌥D showed the desktop. Pure, unit-tested.
struct ShowDesktopFront: Equatable {
    let pid: pid_t
    /// Nil when DockFlip knew no window of it (an app with its windows closed).
    let windowID: CGWindowID?

    /// What gets the keyboard back as the desktop is hidden again: the front from
    /// before, but only if Show Desktop hid its app and is now unhiding it. An app
    /// the user brought back by hand, or one that quit, is left as it is.
    static func toRestore(_ front: ShowDesktopFront?, unhidden: [pid_t]) -> ShowDesktopFront? {
        guard let front, unhidden.contains(front.pid) else { return nil }
        return front
    }
}
