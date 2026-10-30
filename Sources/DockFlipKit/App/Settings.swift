import AppKit
import Combine
import ServiceManagement

/// The user settings (see SCOPE.md). Everything lives in UserDefaults; nothing
/// leaves the Mac. Views observe this object; services read it when they act.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let previews = "previewsEnabled"
        static let shortcuts = "shortcutsEnabled"
        static let onboarded = "onboardingCompleted"
        static let debug = "debugLogging"
    }

    private let defaults: UserDefaults
    /// True for a key an MDM profile sets (managed preferences, see docs/IT.md).
    private let isForced: (String) -> Bool

    /// Window pictures in the Dock list and ⌘Tab (needs Screen Recording).
    @Published var previewsEnabled: Bool {
        didSet {
            // A managed key keeps its forced value: UserDefaults keeps returning it, so the
            // features must follow it now, not only after the next launch.
            if let forced = forcedValue(Key.previews) {
                if previewsEnabled != forced { previewsEnabled = forced }
            } else {
                defaults.set(previewsEnabled, forKey: Key.previews)
            }
        }
    }
    /// ⌘Tab and the ⌃⌥ shortcuts.
    @Published var shortcutsEnabled: Bool {
        didSet {
            if let forced = forcedValue(Key.shortcuts) {
                if shortcutsEnabled != forced { shortcutsEnabled = forced }
            } else {
                defaults.set(shortcutsEnabled, forKey: Key.shortcuts)
            }
        }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarded) }
    }
    /// Not a user setting as such: a troubleshooting switch in the menu bar menu.
    @Published var debugLogging: Bool {
        didSet { defaults.set(debugLogging, forKey: Key.debug) }
    }

    /// The organization's profile sets this; Settings shows it locked.
    var previewsManaged: Bool { isForced(Key.previews) }
    var shortcutsManaged: Bool { isForced(Key.shortcuts) }

    /// `defaults` and `isForced` are for tests; `isForced` defaults to asking `defaults`.
    init(defaults: UserDefaults = .standard, isForced: ((String) -> Bool)? = nil) {
        self.defaults = defaults
        self.isForced = isForced ?? { defaults.objectIsForced(forKey: $0) }
        defaults.register(defaults: [
            Key.previews: false,
            Key.shortcuts: true,
            Key.onboarded: false,
            Key.debug: false
        ])
        previewsEnabled = defaults.bool(forKey: Key.previews)
        shortcutsEnabled = defaults.bool(forKey: Key.shortcuts)
        onboardingCompleted = defaults.bool(forKey: Key.onboarded)
        debugLogging = defaults.bool(forKey: Key.debug)
    }

    /// The value a profile forces for `key`, or nil when the user may change it.
    private func forcedValue(_ key: String) -> Bool? {
        isForced(key) ? defaults.bool(forKey: key) : nil
    }

    /// Lives in macOS (Login Items), not in UserDefaults.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
            objectWillChange.send()
        }
    }
}
