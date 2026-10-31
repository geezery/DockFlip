import AppKit
import Combine

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
        static let switcherStyle = "switcherStyle"
    }

    private let defaults: UserDefaults
    /// True for a key an MDM profile sets (managed preferences, see docs/IT.md).
    private let isForced: (String) -> Bool
    private let loginItem: any LoginItem
    /// Tokens for the managed-preferences observers; Settings lives as long as the app.
    private var managedObservers: [NSObjectProtocol] = []

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
    /// How ⌘Tab looks: Flip 3D (Windows 7) or the grid (Windows 11).
    @Published var switcherStyle: SwitcherStyle {
        didSet {
            if isForced(Key.switcherStyle) {
                let forced = SwitcherStyle(stored: defaults.string(forKey: Key.switcherStyle))
                if switcherStyle != forced { switcherStyle = forced }
            } else {
                defaults.set(switcherStyle.rawValue, forKey: Key.switcherStyle)
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
    var switcherStyleManaged: Bool { isForced(Key.switcherStyle) }

    /// Why the last Launch at login change didn't take; Settings shows it under the switch.
    @Published private(set) var launchAtLoginProblem: LoginItemProblem? = nil

    /// `defaults`, `isForced` and `loginItem` are for tests; `isForced` defaults to asking `defaults`.
    init(
        defaults: UserDefaults = .standard,
        isForced: ((String) -> Bool)? = nil,
        loginItem: any LoginItem = MainAppLoginItem()
    ) {
        self.defaults = defaults
        self.isForced = isForced ?? { defaults.objectIsForced(forKey: $0) }
        self.loginItem = loginItem
        defaults.register(defaults: [
            Key.previews: false,
            Key.shortcuts: true,
            Key.onboarded: false,
            Key.debug: false,
            Key.switcherStyle: SwitcherStyle.flip3D.rawValue
        ])
        previewsEnabled = defaults.bool(forKey: Key.previews)
        shortcutsEnabled = defaults.bool(forKey: Key.shortcuts)
        switcherStyle = SwitcherStyle(stored: defaults.string(forKey: Key.switcherStyle))
        onboardingCompleted = defaults.bool(forKey: Key.onboarded)
        debugLogging = defaults.bool(forKey: Key.debug)
        observeManagedChanges()
    }

    /// An MDM profile installed or removed while DockFlip runs: macOS posts the MCX
    /// notification (and UserDefaults its change) but nothing re-reads our copies, so
    /// without this the profile only took effect after a relaunch.
    private func observeManagedChanges() {
        let reload: @Sendable (Notification) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadManaged() }
        }
        managedObservers = [
            NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: defaults, queue: .main, using: reload),
            DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("com.apple.MCX._managementStatusChangedForDomains"),
                object: nil, queue: .main, using: reload)
        ]
    }

    /// Reads the profile-managed keys again: a newly forced value wins, and a removed
    /// profile hands the key back to the user's own saved value.
    func reloadManaged() {
        objectWillChange.send() // previewsManaged / shortcutsManaged may have changed.
        let previews = defaults.bool(forKey: Key.previews)
        if previewsEnabled != previews { previewsEnabled = previews }
        let shortcuts = defaults.bool(forKey: Key.shortcuts)
        if shortcutsEnabled != shortcuts { shortcutsEnabled = shortcuts }
        let style = SwitcherStyle(stored: defaults.string(forKey: Key.switcherStyle))
        if switcherStyle != style { switcherStyle = style }
    }

    /// The value a profile forces for `key`, or nil when the user may change it.
    private func forcedValue(_ key: String) -> Bool? {
        isForced(key) ? defaults.bool(forKey: key) : nil
    }

    /// Lives in macOS (Login Items), not in UserDefaults.
    var launchAtLogin: Bool {
        get { loginItem.status == .enabled }
        set {
            var failure: String?
            do {
                if newValue { try loginItem.register() } else { try loginItem.unregister() }
            } catch {
                failure = error.localizedDescription
                Log.app.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
            }
            objectWillChange.send()
            launchAtLoginProblem = LoginItemProblem.after(wanting: newValue, status: loginItem.status, error: failure)
        }
    }

    /// Reads Login Items again, after the user may have changed it in System Settings.
    func refreshLaunchAtLogin() {
        objectWillChange.send()
        let problem = launchAtLoginProblem?.refreshed(status: loginItem.status)
        if problem != launchAtLoginProblem { launchAtLoginProblem = problem }
    }

    func openLoginItemsSettings() {
        loginItem.openSystemSettings()
    }
}
