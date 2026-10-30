import Foundation
import Testing
@testable import DockFlipKit

/// A Launch at login change macOS doesn't take shows why under the switch, instead of
/// the switch just flipping back. `FakeLoginItem` stands in for `SMAppService`.
@Suite("Settings: launch at login")
@MainActor
struct LoginItemTests {
    private struct Refused: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    private final class FakeLoginItem: LoginItem {
        var status: LoginItemStatus
        /// The status a register() call leaves behind, and what it throws.
        var statusAfterRegister: LoginItemStatus = .enabled
        var registerError: Error?
        var openedSettings = 0

        init(status: LoginItemStatus) { self.status = status }

        func register() throws {
            status = statusAfterRegister
            if let registerError { throw registerError }
        }
        func unregister() throws { status = .notRegistered }
        func openSystemSettings() { openedSettings += 1 }
    }

    private func makeSettings(_ item: FakeLoginItem) -> (Settings, UserDefaults, String) {
        let name = "DockFlipTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (Settings(defaults: defaults, isForced: { _ in false }, loginItem: item), defaults, name)
    }

    @Test func switchedOffInLoginItemsAsksForApproval() {
        // The user switched DockFlip off in System Settings: register() throws and the
        // status stays requiresApproval.
        let item = FakeLoginItem(status: .requiresApproval)
        item.statusAfterRegister = .requiresApproval
        item.registerError = Refused()
        let (settings, defaults, suite) = makeSettings(item)
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.launchAtLogin = true

        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginProblem == .needsApproval)
        settings.openLoginItemsSettings()
        #expect(item.openedSettings == 1)
    }

    @Test func approvalNoteGoesOnceAllowedInSystemSettings() {
        let item = FakeLoginItem(status: .requiresApproval)
        item.statusAfterRegister = .requiresApproval
        let (settings, defaults, suite) = makeSettings(item)
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.launchAtLogin = true
        #expect(settings.launchAtLoginProblem == .needsApproval)

        settings.refreshLaunchAtLogin()
        #expect(settings.launchAtLoginProblem == .needsApproval)

        item.status = .enabled
        settings.refreshLaunchAtLogin()
        #expect(settings.launchAtLoginProblem == nil)
        #expect(settings.launchAtLogin)
    }

    @Test func refusalShowsMacOSWords() {
        let item = FakeLoginItem(status: .notRegistered)
        item.statusAfterRegister = .notRegistered
        item.registerError = Refused()
        let (settings, defaults, suite) = makeSettings(item)
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.launchAtLogin = true

        #expect(settings.launchAtLoginProblem == .failed("Operation not permitted"))
        // The words stay up when the window comes forward again, until the switch is used.
        settings.refreshLaunchAtLogin()
        #expect(settings.launchAtLoginProblem == .failed("Operation not permitted"))
    }

    @Test func aChangeThatTakesShowsNothing() {
        let item = FakeLoginItem(status: .notRegistered)
        let (settings, defaults, suite) = makeSettings(item)
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.launchAtLogin = true
        #expect(settings.launchAtLogin)
        #expect(settings.launchAtLoginProblem == nil)

        settings.launchAtLogin = false
        #expect(!settings.launchAtLogin)
        #expect(settings.launchAtLoginProblem == nil)
    }

    @Test func turningOffClearsAnEarlierProblem() {
        let item = FakeLoginItem(status: .requiresApproval)
        item.statusAfterRegister = .requiresApproval
        let (settings, defaults, suite) = makeSettings(item)
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.launchAtLogin = true
        #expect(settings.launchAtLoginProblem == .needsApproval)

        settings.launchAtLogin = false

        #expect(settings.launchAtLoginProblem == nil)
    }

    @Test func silentRefusalStillSaysSomething() {
        #expect(LoginItemProblem.after(wanting: true, status: .notFound, error: nil) == .failed(nil))
        #expect(LoginItemProblem.after(wanting: false, status: .enabled, error: nil) == .failed(nil))
        #expect(LoginItemProblem.after(wanting: false, status: .requiresApproval, error: nil) == nil)
        #expect(LoginItemProblem.after(wanting: true, status: .requiresApproval, error: "x") == .needsApproval)
    }
}
