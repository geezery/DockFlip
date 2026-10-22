import AppKit
import ApplicationServices

enum Permissions {
    /// True when Plinth may use the Accessibility API and create event taps.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Adds Plinth to the Accessibility list (switched off) and opens the right
    /// pane of System Settings, so the user only has to flip one switch.
    static func requestAccessibility() {
        // "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
