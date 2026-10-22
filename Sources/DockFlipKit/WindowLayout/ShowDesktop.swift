import AppKit

/// Windows' "Show desktop" (Win+D, here ⌃⌥D): hides every app; pressing it
/// again brings back the ones it hid.
@MainActor
enum ShowDesktop {
    private static var hiddenApps: [NSRunningApplication] = []

    static func toggle() {
        let stillHidden = hiddenApps.filter { !$0.isTerminated && $0.isHidden }
        if !stillHidden.isEmpty {
            for app in stillHidden { app.unhide() }
            hiddenApps = []
            return
        }
        let own = ProcessInfo.processInfo.processIdentifier
        hiddenApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != own && app.hide()
        }
    }
}
