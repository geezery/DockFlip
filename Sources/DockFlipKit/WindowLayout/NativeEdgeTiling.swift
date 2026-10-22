import AppKit

/// macOS 15+ tiles windows dragged to screen edges, on by default. It competes
/// with DockFlip's drag snapping (two previews, two layouts), so setup offers to
/// turn it off. Nothing changes unless the user presses that button.
enum NativeEdgeTiling {
    private static let domain = "com.apple.WindowManager" as CFString
    private static let keys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag"]

    static var isOn: Bool {
        keys.contains { CFPreferencesCopyAppValue($0 as CFString, domain) as? Bool ?? true }
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
