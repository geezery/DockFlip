import AppKit
import ApplicationServices

/// The one permission DockFlip needs: Accessibility.
enum Permissions {
    /// True when DockFlip may use the Accessibility API and create event taps.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Adds DockFlip to the Accessibility list (switched off) and opens the right
    /// pane of System Settings, so the user only has to flip one switch.
    static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clears a stale Accessibility entry. macOS ties the permission to the app's
    /// signature; after a rebuild with a different signature the switch in System
    /// Settings still shows "on" but no longer applies. Resetting removes the old
    /// entry, so the next request adds a fresh one.
    @discardableResult
    static func resetAccessibility() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            Log.app.notice("tccutil reset Accessibility: \(ok ? "ok" : "failed", privacy: .public)")
            return ok
        } catch {
            return false
        }
    }
}
