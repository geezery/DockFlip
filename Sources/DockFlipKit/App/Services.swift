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

    /// True when DockFlip's ⌘Tab works right now. The ⌃⌥ shortcuts don't count:
    /// with them alone ⌘Tab is macOS's (or another app's).
    var shortcutsActive: Bool {
        Settings.shared.shortcutsEnabled && hotKeys.ownsCommandTab && tapsRunning
    }

    /// True when DockFlip wants ⌘Tab but another app (AltTab) holds it.
    var commandTabHeldElsewhere: Bool {
        Settings.shared.shortcutsEnabled && hotKeys.registration.commandTabFailed
    }

    /// The one later attempt at ⌘Tab after another app held it.
    private var commandTabRetry: Task<Void, Never>?

    /// ⌘Tab and the ⌃⌥ shortcuts belong to DockFlip while the setting is on;
    /// otherwise macOS gets ⌘Tab back.
    func applyShortcutSetting() {
        commandTabRetry?.cancel()
        commandTabRetry = nil
        guard Settings.shared.shortcutsEnabled else {
            hotKeys.unregisterAll()
            NativeCommandTab.setEnabled(true)
            return
        }
        takeShortcuts()
        guard !hotKeys.ownsCommandTab else { return }
        // On Restart DockFlip the old instance holds ⌘Tab until it has quit, which
        // can be after this one starts: ask once more. Not a poll: one try only.
        commandTabRetry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, Settings.shared.shortcutsEnabled else { return }
            self.commandTabRetry = nil
            self.takeShortcuts()
        }
    }

    /// Registers the shortcuts. macOS's own ⌘Tab goes off first, as AltTab does, and
    /// back on when another app holds ⌘Tab: otherwise ⌘Tab would do nothing at all.
    private func takeShortcuts() {
        NativeCommandTab.setEnabled(false)
        hotKeys.registerAll()
        if !hotKeys.ownsCommandTab {
            NativeCommandTab.setEnabled(true)
            Log.keys.error("Another app holds ⌘Tab: macOS keeps its own ⌘Tab")
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
        commandTabRetry?.cancel()
        // Give ⌘Tab back to macOS — unless a new DockFlip instance is taking over.
        if !handingOver { NativeCommandTab.setEnabled(true) }
        hotKeys.unregisterAll()
        usage.saveNow()
    }

    /// Lines for the debug log.
    func debugLines() -> [String] {
        let failed = hotKeys.registration.failed.map(\.shortcutName).joined(separator: " ")
        return registry.debugSummary() + [
            "hotKeys=\(hotKeys.registeredCount) commandTab=\(hotKeys.ownsCommandTab) failed=[\(failed)] keyTaps=\(tapsRunning) secureInput=\(IsSecureEventInputEnabled()) cleanupSuggestions=\(cleanup.candidateCount())"
        ]
    }
}
