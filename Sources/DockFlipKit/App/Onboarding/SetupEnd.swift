import Foundation

/// The settings setup writes when it ends. `Settings` is the real one; tests pass a stand-in,
/// because Launch at login lives in macOS (`SMAppService`), which a test can't touch.
@MainActor
protocol SetupSettings: AnyObject {
    var previewsEnabled: Bool { get set }
    var launchAtLogin: Bool { get set }
    var onboardingCompleted: Bool { get set }
    /// Why the last Launch at login write didn't take, if it didn't.
    var launchAtLoginProblem: LoginItemProblem? { get }
}

extension Settings: SetupSettings {}

/// How setup ends, by Continue on the last step or by the window's close button. Both save
/// the same choices, so closing early never skips Launch at login (on by default, SCOPE.md).
@MainActor
enum SetupEnd {
    /// Saves the choices once Accessibility is allowed and returns true: DockFlip starts.
    /// Without the permission it saves nothing and returns false, so setup comes back.
    /// `previews` is nil when the question wasn't answered: the setting stays as it is.
    @discardableResult
    static func save(previews: Bool?, launchAtLogin: Bool, trusted: Bool, to settings: SetupSettings) -> Bool {
        guard trusted else { return false }
        if let previews { settings.previewsEnabled = previews }
        // Each write registers or unregisters the login item: write only a change.
        if launchAtLogin != settings.launchAtLogin { settings.launchAtLogin = launchAtLogin }
        settings.onboardingCompleted = true
        return true
    }

    /// What the user must be told after setup ends: a Launch at login write macOS refused.
    /// Setup closes as it saves, so the warning has to go where it can be seen (Settings);
    /// otherwise DockFlip quietly wouldn't start at the next login.
    static func problemToShow(started: Bool, settings: SetupSettings) -> LoginItemProblem? {
        started ? settings.launchAtLoginProblem : nil
    }

    /// The switch setup starts with: on for a first setup, and the user's own choice when
    /// setup comes back after it was finished once (Accessibility was taken away).
    static func initialLaunchAtLogin(completedBefore: Bool, current: Bool) -> Bool {
        completedBefore ? current : true
    }
}
