/// A feature that a broken private macOS call or Dock hook has taken away, for the
/// menu bar menu's status lines: whoever finds the Dock lists dead reads why there
/// instead of guessing. The failures are the ones the debug log's Self-check section
/// writes in capitals; "not tried yet", "attached, no hover" and "none found" are
/// not failures, so they show nothing.
enum UnavailableFeature: Equatable, CaseIterable {
    /// `CGSSetSymbolicHotKeyEnabled` is missing or never worked: macOS's own ⌘Tab
    /// stays on beside DockFlip's.
    case commandTabSwitchOff
    /// `_AXUIElementGetWindow` answered for no window: DockFlip sees none.
    case windowTracking
    /// No element answered a search for windows on other Spaces or in full screen.
    case otherSpaces
    /// The observer on the Dock's icon list could not attach: no list on hover.
    case dockLists

    /// What `check` says is unavailable, in the debug log's order.
    /// - accessibilityAllowed: without it every call fails, and the menu offers
    ///   Grant Accessibility instead of blaming macOS.
    /// - commandTabSwitchFound: `NativeCommandTab.isAvailable`.
    /// - ownsCommandTab: DockFlip holds ⌘Tab (`Services.shortcutsActive`). Otherwise
    ///   macOS's own ⌘Tab is meant to stay on, and calls made to give it back don't count.
    static func list(_ check: SelfCheck, accessibilityAllowed: Bool,
                     commandTabSwitchFound: Bool, ownsCommandTab: Bool) -> [UnavailableFeature] {
        guard accessibilityAllowed else { return [] }
        var features: [UnavailableFeature] = []
        let switchCalls = check.commandTabSwitch
        if ownsCommandTab, !commandTabSwitchFound || (switchCalls.total > 0 && switchCalls.succeeded == 0) {
            features.append(.commandTabSwitchOff)
        }
        if check.windowIDs.total > 0, check.windowIDs.succeeded == 0 {
            features.append(.windowTracking)
        }
        if check.walk.searches > 0, check.walk.found == 0, check.walk.answered == 0 {
            features.append(.otherSpaces)
        }
        if case .failed = check.dock {
            features.append(.dockLists)
        }
        return features
    }
}
