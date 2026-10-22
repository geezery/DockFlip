import Darwin

/// Turns the system's own ⌘Tab app switcher off while Plinth runs, so ⌘Tab
/// opens Plinth's window switcher instead. Quitting Plinth turns it back on.
///
/// Uses the private `CGSSetSymbolicHotKeyEnabled` (same approach as AltTab),
/// looked up at runtime so a missing symbol can never break the build or launch.
enum NativeCommandTab {
    private typealias SetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> Int32

    /// Symbolic hot key ids: 1 = ⌘Tab, 2 = ⌘⇧Tab.
    private static let hotKeys: [Int32] = [1, 2]

    private static let setter: SetSymbolicHotKeyEnabled? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let symbol = dlsym(handle, "CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: SetSymbolicHotKeyEnabled.self)
    }()

    static func setEnabled(_ enabled: Bool) {
        guard let setter else { return }
        for hotKey in hotKeys {
            _ = setter(hotKey, enabled)
        }
    }
}
