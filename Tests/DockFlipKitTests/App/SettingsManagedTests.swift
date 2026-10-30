import Foundation
import Testing
@testable import DockFlipKit

/// Keys an MDM profile forces (docs/IT.md) stay put, and Settings shows them as managed.
/// A plain suite can't hold managed preferences, so `isForced` stands in for the profile.
@Suite("Settings: managed keys")
@MainActor
struct SettingsManagedTests {
    /// Fresh defaults with `values` set, as a profile would leave them, and their suite name.
    private func makeDefaults(_ values: [String: Bool]) -> (UserDefaults, String) {
        let name = "DockFlipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        for (key, value) in values { defaults.set(value, forKey: key) }
        return (defaults, name)
    }

    @Test func forcedThumbnailsStayOffAndShowManaged() {
        let (defaults, suite) = makeDefaults(["previewsEnabled": false])
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, isForced: { $0 == "previewsEnabled" })
        #expect(settings.previewsManaged)
        #expect(!settings.shortcutsManaged)

        settings.previewsEnabled = true

        #expect(!settings.previewsEnabled)
        #expect(defaults.object(forKey: "previewsEnabled") as? Bool == false)
    }

    @Test func forcedShortcutsStayOn() {
        let (defaults, suite) = makeDefaults(["shortcutsEnabled": true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults, isForced: { $0 == "shortcutsEnabled" })
        #expect(settings.shortcutsManaged)

        settings.shortcutsEnabled = false

        #expect(settings.shortcutsEnabled)
    }

    @Test func unmanagedKeysAreSavedAndEditable() {
        let (defaults, suite) = makeDefaults([:])
        defer { defaults.removePersistentDomain(forName: suite) }
        // No stand-in: the real objectIsForced answers, and nothing manages a test suite.
        let settings = Settings(defaults: defaults)
        #expect(!settings.previewsManaged)
        #expect(!settings.shortcutsManaged)

        settings.previewsEnabled = true
        settings.shortcutsEnabled = false

        #expect(settings.previewsEnabled)
        #expect(defaults.object(forKey: "previewsEnabled") as? Bool == true)
        #expect(defaults.object(forKey: "shortcutsEnabled") as? Bool == false)
    }
}
