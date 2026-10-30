import AppKit

/// macOS 15+ tiles windows dragged to screen edges, on by default. It competes
/// with DockFlip's drag snapping (two previews, two layouts), so setup offers to
/// turn it off, and the menu bar menu offers it again whenever it is back on.
/// Nothing changes unless the user presses that button.
enum NativeEdgeTiling {
    private static let domain = "com.apple.WindowManager" as CFString
    static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]

    static var isOn: Bool {
        // A running app keeps its own copy of another app's preferences. Syncing
        // first reads the current value, so a switch flipped in System Settings
        // (or reset by a macOS update) shows the next time the menu opens.
        CFPreferencesAppSynchronize(domain)
        return isOn(reading: { CFPreferencesCopyAppValue($0 as CFString, domain) as? Bool })
    }

    /// The rule behind `isOn`: a key macOS has never written means the default,
    /// which is on, so tiling is off only when every key says false.
    static func isOn(reading value: (String) -> Bool?) -> Bool {
        keys.contains { value($0) ?? true }
    }

    /// Turns it off and restarts WindowManager, which macOS relaunches at once.
    static func turnOff() {
        for key in keys {
            CFPreferencesSetAppValue(key as CFString, kCFBooleanFalse, domain)
        }
        CFPreferencesAppSynchronize(domain)
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager") {
            app.forceTerminate()
        }
    }
}
