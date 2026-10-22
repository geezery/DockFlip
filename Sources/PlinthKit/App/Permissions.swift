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

/// Brings one of Plinth's own windows to the front.
///
/// Plinth is an accessory app, and since macOS 14 activation is cooperative:
/// when Plinth starts from Terminal (`make install`) or from its menu bar item,
/// macOS may refuse to activate it and the window would open behind other apps.
/// `orderFrontRegardless` puts the window in front even then.
@MainActor
enum WindowPresenter {
    static func bringToFront(_ window: NSWindow) {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
