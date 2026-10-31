import Foundation
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
        var previewsManaged = false
        var loginItem = false
        var loginItemWrites = 0
        /// Set to make the login item refuse writes, as macOS does when DockFlip is
        /// switched off in Login Items.
        var refusal: LoginItemProblem?
        var launchAtLoginProblem: LoginItemProblem?
        var launchAtLogin: Bool {
            get { loginItem }
            set {
                loginItemWrites += 1
                if let refusal { launchAtLoginProblem = refusal } else { loginItem = newValue; launchAtLoginProblem = nil }
            }
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

    @Test func refusedLaunchAtLoginIsShownAfterSetup() {
        let settings = FakeSettings()
        settings.refusal = .needsApproval
        let started = SetupEnd.save(previews: nil, launchAtLogin: true, trusted: true, to: settings)
        let problem = SetupEnd.problemToShow(started: started, settings: settings)

        #expect(started)
        #expect(!settings.launchAtLogin)
        #expect(problem == .needsApproval)
    }

    private struct Refused: Error {}

    /// The real Settings over a login item that throws, as SMAppService does when DockFlip
    /// is switched off in Login Items.
    private final class RefusingLoginItem: LoginItem {
        var status: LoginItemStatus { .requiresApproval }
        func register() throws { throw Refused() }
        func unregister() throws {}
        func openSystemSettings() {}
    }

    @Test func throwingLoginItemLeavesTheProblemToShow() {
        let name = "DockFlipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = Settings(defaults: defaults, isForced: { _ in false }, loginItem: RefusingLoginItem())
        let started = SetupEnd.save(previews: nil, launchAtLogin: true, trusted: true, to: settings)
        let problem = SetupEnd.problemToShow(started: started, settings: settings)

        #expect(started)
        #expect(problem == .needsApproval)
    }

    @Test func acceptedLaunchAtLoginShowsNothing() {
        let settings = FakeSettings()
        let started = SetupEnd.save(previews: nil, launchAtLogin: true, trusted: true, to: settings)
        let problem = SetupEnd.problemToShow(started: started, settings: settings)

        #expect(problem == nil)
    }

    /// The real Settings under a profile that forces thumbnails off: the setup answer
    /// must not be written, and the managed key must keep its forced value.
    @Test func managedPreviewsIgnoreTheSetupAnswer() {
        let name = "DockFlipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(false, forKey: "previewsEnabled")
        let settings = Settings(defaults: defaults, isForced: { $0 == "previewsEnabled" }, loginItem: RefusingLoginItem())
        let started = SetupEnd.save(previews: true, launchAtLogin: false, trusted: true, to: settings)
        let stored = defaults.object(forKey: "previewsEnabled") as? Bool

        #expect(started)
        #expect(settings.previewsManaged)
        #expect(!settings.previewsEnabled)
        #expect(stored == false)
    }

    @Test func managedPreviewsSkipTheThumbnailsStep() {
        let managed = OnboardingModel.Step.shown(previewsManaged: true)
        let free = OnboardingModel.Step.shown(previewsManaged: false)

        #expect(managed == [.welcome, .accessibility, .finish])
        #expect(free == [.welcome, .accessibility, .previews, .finish])
    }

    @Test func nextAndBackStepOverTheManagedStep() {
        let model = OnboardingModel(previewsManaged: true)
        model.granted = true
        model.step = .accessibility
        model.next()
        let afterNext = model.step
        model.back()
        let afterBack = model.step

        #expect(afterNext == .finish)
        #expect(afterBack == .accessibility)
    }

    @Test func launchAtLoginStartsOnOnlyForAFirstSetup() {
        #expect(SetupEnd.initialLaunchAtLogin(completedBefore: false, current: false))
        #expect(!SetupEnd.initialLaunchAtLogin(completedBefore: true, current: false))
        #expect(SetupEnd.initialLaunchAtLogin(completedBefore: true, current: true))
    }
}
