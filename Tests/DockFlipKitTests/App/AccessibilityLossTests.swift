import Testing
@testable import DockFlipKit

/// Accessibility switched off while DockFlip runs must not leave a ⌘Tab that shows
/// windows but cannot switch: ⌘Tab goes back to macOS, and coming back restarts DockFlip.
@Suite("Accessibility taken away while DockFlip runs")
struct AccessibilityLossTests {
    @Test func switchedOffGivesTheShortcutsBack() {
        #expect(AccessibilityLoss.action(granted: false, servicesStarted: true, suspended: false) == .giveBackShortcuts)
    }

    @Test func switchedBackOnRestarts() {
        #expect(AccessibilityLoss.action(granted: true, servicesStarted: true, suspended: true) == .restart)
    }

    @Test func repeatedAnswersDoNothingMore() {
        // A second "off" (another app's switch flipped) must not open setup again.
        #expect(AccessibilityLoss.action(granted: false, servicesStarted: true, suspended: true) == .none)
        #expect(AccessibilityLoss.action(granted: true, servicesStarted: true, suspended: false) == .none)
    }

    @Test func beforeTheFeaturesStartSetupDecides() {
        for granted in [false, true] {
            for suspended in [false, true] {
                #expect(AccessibilityLoss.action(granted: granted, servicesStarted: false, suspended: suspended) == .none)
            }
        }
    }

    @Test func lostPermissionKeepsCommandTabWithMacOS() {
        #expect(AccessibilityLoss.takesShortcuts(enabled: true, suspended: false))
        #expect(!AccessibilityLoss.takesShortcuts(enabled: true, suspended: true))
        // Turning the shortcut setting on again while suspended must not take ⌘Tab.
        #expect(!AccessibilityLoss.takesShortcuts(enabled: false, suspended: true))
        #expect(!AccessibilityLoss.takesShortcuts(enabled: false, suspended: false))
    }
}
