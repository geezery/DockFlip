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

    /// Stands in for a profile that can be installed and removed while the app runs.
    private final class Profile: @unchecked Sendable { var forced: Set<String> = [] }

    @Test func profileInstalledWhileRunningTakesEffectAtOnce() {
        let (defaults, suite) = makeDefaults(["previewsEnabled": true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = Profile()
        let settings = Settings(defaults: defaults, isForced: { profile.forced.contains($0) })
        #expect(settings.previewsEnabled)
        #expect(!settings.previewsManaged)

        // The profile lands: the key is forced off.
        profile.forced = ["previewsEnabled"]
        defaults.set(false, forKey: "previewsEnabled")
        settings.reloadManaged()

        #expect(!settings.previewsEnabled)
        #expect(settings.previewsManaged)
        settings.previewsEnabled = true
        #expect(!settings.previewsEnabled)
    }

    @Test func profileRemovedWhileRunningHandsTheKeyBack() {
        let (defaults, suite) = makeDefaults(["shortcutsEnabled": true])
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = Profile()
        profile.forced = ["shortcutsEnabled"]
        let settings = Settings(defaults: defaults, isForced: { profile.forced.contains($0) })

        profile.forced = []
        defaults.set(false, forKey: "shortcutsEnabled") // The user's own value shows again.
        settings.reloadManaged()

        #expect(!settings.shortcutsManaged)
        #expect(!settings.shortcutsEnabled)
        settings.shortcutsEnabled = true
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
