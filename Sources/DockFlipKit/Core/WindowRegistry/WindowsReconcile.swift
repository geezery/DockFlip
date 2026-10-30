import CoreGraphics

/// What one read of an app's windows (`WindowsRead`) means for the windows
/// DockFlip already knows of it.
struct WindowsReconcile: Equatable {
    /// Known windows neither Accessibility nor the window server lists any more.
    var gone: Set<CGWindowID> = []
    /// A window did not answer in time: read the app again shortly.
    var readAgain = false

    /// `listed`: each window the app listed, and whether it is a standard window
    /// (nil: its role did not arrive in time). `inventory`: the app's windows the
    /// window server knows, on every Space.
    static func after(
        listed: [(id: CGWindowID, isStandard: Bool?)],
        known: Set<CGWindowID>,
        inventory: Set<CGWindowID>
    ) -> WindowsReconcile {
        var result = WindowsReconcile()
        var seen = Set<CGWindowID>()
        for window in listed {
            guard let isStandard = window.isStandard else {
                // A failed read is not an answer: a window whose role did not arrive
                // in time is kept if known, and read again shortly — never dropped.
                result.readAgain = true
                if known.contains(window.id) { seen.insert(window.id) }
                continue
            }
            if isStandard { seen.insert(window.id) }
        }
        // Windows on other Spaces are missing from kAXWindows; the window server
        // still lists them. Only windows it no longer knows are gone.
        result.gone = known.subtracting(seen).subtracting(inventory)
        return result
    }
}
