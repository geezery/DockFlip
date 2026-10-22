import AppKit
import Combine
import ServiceManagement

/// The user settings (see SCOPE.md), plus internal state such as pinned apps.
/// Everything is stored in UserDefaults; nothing leaves the Mac.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private enum Key {
        static let previews = "previewsEnabled"
        static let combine = "combineTaskbarButtons"
        static let allDisplays = "taskbarOnAllDisplays"
        static let shortcuts = "shortcutsEnabled"
        static let pinned = "pinnedBundleIDs"
        static let folders = "pinnedFolderPaths"
        static let onboarded = "onboardingCompleted"
        static let schema = "settingsSchema"
        static let debug = "debugLogging"
        static let useDock = "useDock"
    }

    private let defaults = UserDefaults.standard

    @Published var previewsEnabled: Bool {
        didSet { defaults.set(previewsEnabled, forKey: Key.previews) }
    }
    @Published var combineButtons: Bool {
        didSet { defaults.set(combineButtons, forKey: Key.combine) }
    }
    @Published var taskbarOnAllDisplays: Bool {
        didSet { defaults.set(taskbarOnAllDisplays, forKey: Key.allDisplays) }
    }
    @Published var shortcutsEnabled: Bool {
        didSet { defaults.set(shortcutsEnabled, forKey: Key.shortcuts) }
    }
    @Published var pinnedBundleIDs: [String] {
        didSet { defaults.set(pinnedBundleIDs, forKey: Key.pinned) }
    }
    /// Folders shown next to the clock, like the right side of the Dock.
    @Published var pinnedFolderPaths: [String] {
        didSet { defaults.set(pinnedFolderPaths, forKey: Key.folders) }
    }
    @Published var onboardingCompleted: Bool {
        didSet { defaults.set(onboardingCompleted, forKey: Key.onboarded) }
    }
    /// Not one of the five user settings: a troubleshooting switch in the menu bar menu.
    @Published var debugLogging: Bool {
        didSet { defaults.set(debugLogging, forKey: Key.debug) }
    }
    /// Dock mode (default): Plinth adds window lists and minimize-on-click to the
    /// macOS Dock. Off: Plinth's own Windows-style taskbar. Takes effect on relaunch.
    @Published var useDock: Bool {
        didSet { defaults.set(useDock, forKey: Key.useDock) }
    }

    private init() {
        // A local copy: `self.defaults` cannot be used before every property is set.
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Key.previews: false,
            Key.combine: true,
            Key.allDisplays: true,
            Key.shortcuts: true,
            Key.onboarded: false,
            Key.debug: false,
            Key.useDock: true,
            Key.schema: 1
        ])
        previewsEnabled = defaults.bool(forKey: Key.previews)
        combineButtons = defaults.bool(forKey: Key.combine)
        taskbarOnAllDisplays = defaults.bool(forKey: Key.allDisplays)
        shortcutsEnabled = defaults.bool(forKey: Key.shortcuts)
        onboardingCompleted = defaults.bool(forKey: Key.onboarded)
        debugLogging = defaults.bool(forKey: Key.debug)
        useDock = defaults.bool(forKey: Key.useDock)
        // First launch: start from what the user already has in the Dock.
        // (Locals: properties cannot be read before every one of them is set.)
        let folders = defaults.stringArray(forKey: Key.folders) ?? SystemTweaks.dockFolderPaths()
        let pinned = defaults.stringArray(forKey: Key.pinned) ?? SystemTweaks.dockPinnedBundleIDs()
        defaults.set(folders, forKey: Key.folders)
        defaults.set(pinned, forKey: Key.pinned)
        pinnedFolderPaths = folders
        pinnedBundleIDs = pinned
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSLog("Plinth: launch at login change failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    func isPinned(_ bundleID: String) -> Bool {
        pinnedBundleIDs.contains(bundleID)
    }

    func togglePin(_ bundleID: String) {
        if let index = pinnedBundleIDs.firstIndex(of: bundleID) {
            pinnedBundleIDs.remove(at: index)
        } else {
            pinnedBundleIDs.append(bundleID)
        }
    }
}
