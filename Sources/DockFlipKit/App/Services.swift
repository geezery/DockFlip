import AppKit
import Carbon.HIToolbox

/// Every feature, wired together. Created once Accessibility is allowed (the
/// features cannot work without it) and kept for the life of the app.
///
/// Data flows one way: `WindowRegistry` keeps the windows; the features read
/// it, observe it and act through it. Keyboard shortcuts arrive here and are
/// routed to the feature they belong to (`perform`).
@MainActor
final class Services {
    let registry: WindowRegistry
    let switcher: SwitcherController
    let snapper: SnapController
    let dock: DockController
    let usage: UsageTracker
    let placement: PlacementMemory
    let cleanup: CleanupController
    private let hotKeys = GlobalHotKeys()
    private let keyTaps = SwitcherKeyTaps()
    /// The taps that follow a ⌘Tab session. They need Accessibility, and right
    /// after it is granted macOS sometimes refuses them until DockFlip restarts.
    private(set) var tapsRunning = false

    init() {
        let registry = WindowRegistry()
        let usage = UsageTracker(registry: registry)
        self.registry = registry
        self.usage = usage
        switcher = SwitcherController(registry: registry)
        snapper = SnapController(registry: registry)
        dock = DockController(registry: registry)
        placement = PlacementMemory(registry: registry)
        cleanup = CleanupController(registry: registry, usage: usage)

        registry.start()
        snapper.start()
        dock.start()
        usage.start()
        placement.start()

        // Carbon hot keys start everything (they work even while an app holds
        // secure keyboard input); the key taps follow the ⌘Tab session.
        hotKeys.handler = { [weak self] command in self?.perform(command) }
        keyTaps.onCommandReleased = { [weak self] in _ = self?.switcher.handle(.commandReleased) }
        keyTaps.onEscape = { [weak self] in self?.switcher.handle(.escape) ?? false }
        switcher.onActiveChanged = { [weak self] active in self?.keyTaps.setSwitcherKeysEnabled(active) }
        tapsRunning = keyTaps.start()
        if !tapsRunning {
            Log.keys.error("Could not create the keyboard event taps")
        }
        applyShortcutSetting()
    }

    /// True when ⌘Tab works right now.
    var shortcutsActive: Bool {
        Settings.shared.shortcutsEnabled && hotKeys.registeredCount > 0 && tapsRunning
    }

    /// ⌘Tab and the ⌃⌥ shortcuts belong to DockFlip while the setting is on;
    /// otherwise macOS gets ⌘Tab back.
    func applyShortcutSetting() {
        if Settings.shared.shortcutsEnabled {
            NativeCommandTab.setEnabled(false)
            hotKeys.registerAll()
        } else {
            hotKeys.unregisterAll()
            NativeCommandTab.setEnabled(true)
        }
    }

    /// Runs a keyboard command (also used by the menu bar menu).
    func perform(_ command: HotkeyCommand) {
        switch command {
        case .switcher(let input):
            _ = switcher.handle(input)
        case .snap(let key):
            _ = snapper.handle(key)
        case .moveToDisplay(let key):
            _ = snapper.moveToDisplay(key)
        case .dockItem(let index):
            dock.activateItem(at: index)
        case .showDesktop:
            ShowDesktop.toggle()
        case .newFinderWindow:
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
        }
    }

    func willTerminate(handingOver: Bool) {
        // Give ⌘Tab back to macOS — unless a new DockFlip instance is taking over.
        if !handingOver { NativeCommandTab.setEnabled(true) }
        hotKeys.unregisterAll()
        usage.saveNow()
    }

    /// Lines for the debug log.
    func debugLines() -> [String] {
        registry.debugSummary() + [
            "hotKeys=\(hotKeys.registeredCount) keyTaps=\(tapsRunning) secureInput=\(IsSecureEventInputEnabled()) cleanupSuggestions=\(cleanup.candidateCount())"
        ]
    }
}
