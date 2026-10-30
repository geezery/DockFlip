import Darwin
import OSLog

/// Turns the system's own ⌘Tab app switcher off while DockFlip runs, so ⌘Tab
/// opens DockFlip's window switcher instead. Quitting DockFlip turns it back on.
///
/// Uses the private `CGSSetSymbolicHotKeyEnabled` (same approach as AltTab),
/// looked up at runtime so a missing symbol can never break the build or launch.
enum NativeCommandTab {
    private typealias SetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> Int32

    /// Symbolic hot key ids: 1 = ⌘Tab, 2 = ⌘⇧Tab.
    private static let hotKeys: [Int32] = [1, 2]

    private static let setter: SetSymbolicHotKeyEnabled? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") else {
            Log.keys.error("CGSSetSymbolicHotKeyEnabled not found: macOS's own ⌘Tab stays on")
            return nil
        }
        return unsafeBitCast(symbol, to: SetSymbolicHotKeyEnabled.self)
    }()

    /// False on a macOS without the private call: its own ⌘Tab then stays on
    /// beside DockFlip's, and the debug log's self-check says so.
    static var isAvailable: Bool { setter != nil }

    static func setEnabled(_ enabled: Bool) {
        guard let setter else { return }
        for hotKey in hotKeys {
            let error = setter(hotKey, enabled)
            SelfCheck.record { $0.commandTabSwitch.record(error == 0, error: error) }
            if error != 0 {
                Log.keys.error("CGSSetSymbolicHotKeyEnabled failed for hot key \(hotKey, privacy: .public): error \(error, privacy: .public)")
            }
        }
    }
}
