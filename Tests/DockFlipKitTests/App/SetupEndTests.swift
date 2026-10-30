import Testing
@testable import DockFlipKit

/// Setup saves the same choices whether it ends by Continue or by its close button.
/// The real login item lives in macOS, so a stand-in counts the writes instead.
@Suite("Setup: saving the choices")
@MainActor
struct SetupEndTests {
    @MainActor
    final class FakeSettings: SetupSettings {
        var previewsEnabled = false
        var onboardingCompleted = false
        var loginItem = false
        var loginItemWrites = 0
        var launchAtLogin: Bool {
            get { loginItem }
            set { loginItem = newValue; loginItemWrites += 1 }
        }
    }

    @Test func closingAfterAllowingAccessibilityTurnsOnLaunchAtLogin() {
        let settings = FakeSettings()
        // Closed before the last step: the previews question may be unanswered too.
        let started = SetupEnd.save(previews: nil, launchAtLogin: true, trusted: true, to: settings)

        #expect(started)
        #expect(settings.launchAtLogin)
        #expect(settings.onboardingCompleted)
        #expect(!settings.previewsEnabled)
    }

    @Test func withoutAccessibilityNothingIsSaved() {
        let settings = FakeSettings()
        let started = SetupEnd.save(previews: true, launchAtLogin: true, trusted: false, to: settings)

        #expect(!started)
        #expect(settings.loginItemWrites == 0)
        #expect(!settings.onboardingCompleted)
        #expect(!settings.previewsEnabled)
    }

    @Test func choicesMadeAreSaved() {
        let settings = FakeSettings()
        settings.loginItem = true
        SetupEnd.save(previews: true, launchAtLogin: false, trusted: true, to: settings)

        #expect(settings.previewsEnabled)
        #expect(!settings.launchAtLogin)
    }

    @Test func unchangedLoginItemIsNotWrittenAgain() {
        let settings = FakeSettings()
        settings.loginItem = true
        SetupEnd.save(previews: false, launchAtLogin: true, trusted: true, to: settings)

        #expect(settings.loginItemWrites == 0)
    }

    @Test func unansweredPreviewsKeepTheirSetting() {
        let settings = FakeSettings()
        settings.previewsEnabled = true
        SetupEnd.save(previews: nil, launchAtLogin: true, trusted: true, to: settings)

        #expect(settings.previewsEnabled)
    }

    @Test func launchAtLoginStartsOnOnlyForAFirstSetup() {
        #expect(SetupEnd.initialLaunchAtLogin(completedBefore: false, current: false))
        #expect(!SetupEnd.initialLaunchAtLogin(completedBefore: true, current: false))
        #expect(SetupEnd.initialLaunchAtLogin(completedBefore: true, current: true))
    }
}
