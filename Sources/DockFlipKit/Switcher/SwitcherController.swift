import AppKit
import SwiftUI

/// Drives the ⌘Tab switcher. While it is open, its full-screen panel is the key
/// window and has the keyboard, so the app you came from (say, Terminal) gets no
/// key presses. Releasing ⌘ opens the window in front; Esc or a click outside goes
/// back to where you were.
///
/// The panel is a non-activating panel that is made key *without activating
/// DockFlip* — what AltTab and DockDoor do. Since macOS 14, an app in the background
/// cannot reliably activate itself (cooperative activation), but a non-activating
/// panel can always become key. The app you came from stays the active app, so
/// cancelling needs no re-activation, and keys reach the panel even while that app
/// holds secure keyboard input (where event taps see no key presses at all).
@MainActor
final class SwitcherController {
    private let registry: WindowRegistry
    private let model = SwitcherModel()
    private var panel: NSPanel?
    private var selection: SwitcherSelection?
    /// Every window of this session; `model.items` holds the ones matching the filter.
    private var allWindows: [WindowSnapshot] = []
    private var allItems: [SwitcherItem] = []
    /// Typed filter. Not empty means "search mode": releasing ⌘ no longer
    /// switches, Return does. Cleared whenever the switcher closes.
    private var query = ""
    private var previewTasks: [Task<Void, Never>] = []
    private var previousApp: NSRunningApplication?
    private var localMonitor: Any?
    private var resignKeyToken: NSObjectProtocol?

    /// Called with true when the switcher opens and false when it closes.
    var onActiveChanged: ((Bool) -> Void)?

    var isActive: Bool { selection != nil }

    init(registry: WindowRegistry) {
        self.registry = registry
        model.onPick = { [weak self] index in self?.commit(at: index) }
        model.onCancel = { [weak self] in self?.cancel() }
    }

    /// Returns true when the input was consumed.
    @discardableResult
    func handle(_ input: SwitcherInput) -> Bool {
        switch input {
        case .commandTab(let shift):
            if isActive {
                step(shift ? -1 : 1)
                return true
            }
            return begin(reverse: shift)
        case .right:
            guard isActive else { return false }
            step(1)
            return true
        case .left:
            guard isActive else { return false }
            step(-1)
            return true
        case .enter:
            guard let selection else { return false }
            commit(at: selection.index)
            return true
        case .escape:
            guard isActive else { return false }
            if query.isEmpty {
                cancel()
            } else {
                setQuery("")
            }
            return true
        case .commandReleased:
            if let selection, query.isEmpty { commit(at: selection.index) }
            return false
        case .text(let text):
            guard isActive else { return false }
            setQuery(query + text)
            return true
        case .deleteBackward:
            guard isActive else { return false }
            if !query.isEmpty { setQuery(String(query.dropLast())) }
            return true
        }
    }

    // MARK: - Lifecycle

    private func begin(reverse: Bool) -> Bool {
        Perf.shared.measure("switcher.open") { beginUnmeasured(reverse: reverse) }
    }

    private func beginUnmeasured(reverse: Bool) -> Bool {
        let windows = registry.switcherWindows()
        guard !windows.isEmpty else { return false }

        allWindows = windows
        let previews = PreviewProvider.shared.isAvailable
        query = ""
        model.query = ""
        model.thumbnails = [:]
        model.items = windows.map { window in
            let placement = WindowAppearance.placement(of: window.frame)
            return SwitcherItem(
                windowID: window.id,
                title: window.title.isEmpty ? window.appName : window.title,
                appName: window.appName,
                icon: window.icon,
                minimap: placement?.minimap,
                isMinimized: window.isMinimized,
                isOnOtherSpace: window.isOnOtherSpace,
                document: window.document,
                screenName: placement?.screen.localizedName,
                sizeText: "\(Int(window.frame.width)) × \(Int(window.frame.height))",
                windowSize: window.frame.size,
                tint: WindowAppearance.tint(of: window),
                neverPictured: previews && PreviewProvider.neverPictured(window.bundleID)
            )
        }
        allItems = model.items

        let selection = SwitcherSelection(count: windows.count, reverse: reverse)
        // Open without animating from the previous session's state.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { model.selection = selection.index }
        self.selection = selection

        show()
        onActiveChanged?(true)
        loadPreviews(for: windows)
        return true
    }

    /// Shows only the windows whose title, app or document contains every typed word.
    private func setQuery(_ newQuery: String) {
        query = newQuery
        let matches = allItems.filter { item in
            SwitcherFilter.matches(newQuery, fields: [item.title, item.appName, item.document ?? ""])
        }
        model.query = newQuery
        model.items = matches
        // The best match — the most recently used one — comes to the front.
        var newSelection = SwitcherSelection(count: matches.count, reverse: false)
        newSelection.select(0)
        selection = newSelection
        model.selection = newSelection.index
        let ids = Set(matches.map(\.windowID))
        loadPreviews(for: allWindows.filter { ids.contains($0.id) })
    }

    private func step(_ delta: Int) {
        guard var selection else { return }
        selection.step(delta)
        self.selection = selection
        model.selection = selection.index
    }

    private func commit(at index: Int) {
        guard isActive, model.items.indices.contains(index) else { return }
        let item = model.items[index]
        hide()
        registry.focus(item.windowID)
    }

    private func cancel() {
        guard isActive else { return }
        let previous = previousApp
        let wasActivated = NSApp.isActive
        hide()
        // Normally DockFlip never became active and the previous app still is.
        if wasActivated {
            _ = previous?.activate(from: NSRunningApplication.current, options: [])
        }
    }

    private func hide() {
        previewTasks.forEach { $0.cancel() }
        previewTasks = []
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        panel?.orderOut(nil)
        selection = nil
        allWindows = []
        allItems = []
        query = ""
        model.query = ""
        model.thumbnails = [:]
        previousApp = nil
        onActiveChanged?(false)
    }

    /// Pictures memory already has appear with the stack; fresh ones are
    /// captured side by side, the windows nearest the front first.
    private func loadPreviews(for windows: [WindowSnapshot]) {
        previewTasks.forEach { $0.cancel() }
        previewTasks = []
        guard PreviewProvider.shared.isAvailable else { return }
        let wanted = windows.prefix(16)
        for window in wanted where model.thumbnails[window.id] == nil {
            if let cached = PreviewProvider.shared.cachedThumbnail(for: window.id) {
                model.thumbnails[window.id] = cached
            }
        }
        previewTasks = wanted.map { window in
            Task { @MainActor [weak self] in
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The switcher may have closed while capturing: drop the image then.
                guard !Task.isCancelled, let self, self.isActive, let image else { return }
                self.model.thumbnails[window.id] = image
            }
        }
    }

    // MARK: - Panel

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = DisplayLayout.screen(containingMouse: NSEvent.mouseLocation) else { return }
        panel.setFrame(screen.frame, display: true)

        // Take the keyboard while switching, without activating DockFlip (see the type comment).
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            previousApp = front
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installLocalMonitor()
        let isKey = panel.isKeyWindow
        Log.keys.debug("Switcher panel shown, key window: \(isKey, privacy: .public)")
    }

    /// Another window can take key status while the switcher is open (an app
    /// opening a window, a notification). Take it back on the next turn of the
    /// run loop — making it key again inside the notification is ignored.
    private func observeResignKey(of panel: NSPanel) {
        resignKeyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isActive, let panel = self.panel else { return }
                Log.keys.debug("Switcher panel lost key status; taking it back")
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// The panel is key, so every key but Esc (see `SwitcherKeyTaps`) arrives here
    /// as an ordinary app event, even while another app holds secure keyboard input.
    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let swallow: Bool = MainActor.assumeIsolated { self?.handleLocal(event) ?? false }
            return swallow ? nil : event
        }
    }

    /// Returns true when the event must not reach anything else.
    private func handleLocal(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        if event.type == .flagsChanged {
            if !event.modifierFlags.contains(.command) { handle(.commandReleased) }
            return false
        }
        let input = SwitcherInput.from(
            keyCode: UInt32(event.keyCode),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            text: SwitcherText.typed(event)
        )
        if let input { handle(input) }
        return true // nothing else reaches any app while switching
    }

    private func makePanel() -> NSPanel {
        // Above menus, on every Space and over full-screen apps; takes the keyboard.
        let panel = Panels.make(
            level: .popUpMenu,
            behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle],
            keyable: true
        )

        let hosting = FirstMouseHostingView(rootView: SwitcherView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        observeResignKey(of: panel)
        return panel
    }
}
