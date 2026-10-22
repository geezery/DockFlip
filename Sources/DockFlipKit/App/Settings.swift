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

    private let defaults = UserDefaults.standard

    /// Window pictures in the Dock list and ⌘Tab (needs Screen Recording).
    @Published var previewsEnabled: Bool {
        didSet { defaults.set(previewsEnabled, forKey: Key.previews) }
    }
    /// ⌘Tab and the ⌃⌥ shortcuts.
    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcuts) }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarded) }
    }
    /// Not a user setting as such: a troubleshooting switch in the menu bar menu.
    @Published var debugLogging: Bool {
        didSet { defaults.set(debugLogging, forKey: Key.debug) }
    }

    private init() {
        // A local copy: `self.defaults` cannot be used before every property is set.
        let defaults = UserDefaults.standard
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
