import Foundation
import Testing
@testable import DockFlipKit

/// The ⌘Tab look is saved, defaults to Flip 3D, and an MDM profile can lock it (docs/IT.md).
@Suite("Settings: switcher style")
@MainActor
struct SettingsSwitcherStyleTests {
    /// Fresh defaults with `values` set, and their suite name.
    private func makeDefaults(_ values: [String: String]) -> (UserDefaults, String) {
        let name = "DockFlipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return (defaults, name)
    }

    @Test func flip3DUntilChosenAndTheChoiceIsSaved() {
        let (defaults, suite) = makeDefaults([:])
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        #expect(settings.switcherStyle == .flip3D)
        #expect(!settings.switcherStyleManaged)

        settings.switcherStyle = .grid

        #expect(defaults.string(forKey: "switcherStyle") == "grid")
        #expect(Settings(defaults: defaults).switcherStyle == .grid)
    }

    @Test func anUnknownStoredStyleReadsAsFlip3D() {
        let (defaults, suite) = makeDefaults(["switcherStyle": "coverflow"])
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Settings(defaults: defaults).switcherStyle == .flip3D)
    }

    @Test func aForcedStyleStaysAndShowsManaged() {
        let (defaults, suite) = makeDefaults(["switcherStyle": "grid"])
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, isForced: { $0 == "switcherStyle" })
        #expect(settings.switcherStyle == .grid)
        #expect(settings.switcherStyleManaged)

        settings.switcherStyle = .flip3D

        #expect(settings.switcherStyle == .grid)
        #expect(defaults.string(forKey: "switcherStyle") == "grid")
    }
}
