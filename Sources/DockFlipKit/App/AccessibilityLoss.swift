/// What DockFlip does when the Accessibility switch flips while it runs. Without the
/// permission the Carbon ⌘Tab still opens the switcher, but focusing a window, the key
/// taps and the Dock hook all fail: a ⌘Tab that shows windows and switches nothing.
/// So losing it gives ⌘Tab back to macOS and shows setup, and getting it back restarts
/// DockFlip, because macOS keeps the dead event taps and AX observers dead.
enum AccessibilityLoss {
    enum Action: Equatable {
        /// Nothing to do: setup alone handles the switch before the features start.
        case none
        /// Give ⌘Tab and the ⌃⌥ shortcuts back and open setup's permission step.
        case giveBackShortcuts
        /// The permission is back after it was lost: start fresh.
        case restart
    }

    /// `granted` is the new answer of `AXIsProcessTrusted()`; `suspended` is true once
    /// the shortcuts were given back for a lost permission.
    static func action(granted: Bool, servicesStarted: Bool, suspended: Bool) -> Action {
        guard servicesStarted else { return .none }
        if granted { return suspended ? .restart : .none }
        return suspended ? .none : .giveBackShortcuts
    }

    /// DockFlip holds ⌘Tab only while the setting is on and the permission is there.
    static func takesShortcuts(enabled: Bool, suspended: Bool) -> Bool {
        enabled && !suspended
    }
}
