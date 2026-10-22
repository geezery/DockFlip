import AppKit
import SwiftUI

/// Drives the ⌘Tab switcher. While it is open, Plinth is the active app and its
/// full-screen panel has the keyboard: the app you came from (say, Terminal) gets
/// no key presses, and its secure keyboard input is released. Releasing ⌘ opens
/// the window in front; Esc or a click outside goes back to where you were.
@MainActor
final class SwitcherController {
    private let registry: WindowRegistry
    private let model = SwitcherModel()
    private var panel: NSPanel?
    private var selection: SwitcherSelection?
    private var windowIDs: [CGWindowID] = []
    private var previewTask: Task<Void, Never>?
    private var previousApp: NSRunningApplication?
    private var localMonitor: Any?

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
            cancel()
            return true
        case .commandReleased:
            if let selection { commit(at: selection.index) }
            return false
        }
    }

    // MARK: - Lifecycle

    private func begin(reverse: Bool) -> Bool {
        Perf.shared.measure("switcher.open") { beginUnmeasured(reverse: reverse) }
    }

    private func beginUnmeasured(reverse: Bool) -> Bool {
        let windows = registry.switcherWindows()
        guard !windows.isEmpty else { return false }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let axScreens = screens.map { Geometry.axRect(fromCocoa: $0.frame, primaryHeight: primaryHeight) }

        windowIDs = windows.map(\.id)
        model.thumbnails = [:]
        model.items = windows.map { window in
            let screenIndex = Geometry.bestScreenIndex(for: window.frame, screens: axScreens)
            return SwitcherItem(
                id: window.id,
                title: window.title.isEmpty ? window.appName : window.title,
                appName: window.appName,
                icon: window.icon,
                minimap: screenIndex.map { Geometry.normalized(window.frame, in: axScreens[$0]) },
                isMinimized: window.isMinimized,
                document: window.document,
                screenName: screenIndex.map { screens[$0].localizedName },
                sizeText: "\(Int(window.frame.width)) × \(Int(window.frame.height))",
                tint: IconTint.color(for: window.icon, key: window.bundleID ?? window.appName)
            )
        }

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

    private func step(_ delta: Int) {
        guard var selection else { return }
        selection.step(delta)
        self.selection = selection
        model.selection = selection.index
    }

    private func commit(at index: Int) {
        guard isActive, windowIDs.indices.contains(index) else { return }
        let id = windowIDs[index]
        hide()
        registry.focus(id)
    }

    private func cancel() {
        guard isActive else { return }
        let previous = previousApp
        hide()
        _ = previous?.activate(from: NSRunningApplication.current, options: [])
    }

    private func hide() {
        previewTask?.cancel()
        previewTask = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        panel?.orderOut(nil)
        selection = nil
        windowIDs = []
        model.thumbnails = [:]
        previousApp = nil
        onActiveChanged?(false)
    }

    private func loadPreviews(for windows: [WindowSnapshot]) {
        previewTask?.cancel()
        guard PreviewProvider.shared.isAvailable else { return }
        previewTask = Task { @MainActor [weak self] in
            for window in windows.prefix(12) {
                guard !Task.isCancelled else { return }
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The switcher may have closed while capturing: drop the image then.
                guard !Task.isCancelled, let self, self.isActive else { return }
                if let image { self.model.thumbnails[window.id] = image }
            }
        }
    }

    // MARK: - Panel

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = DisplayLayout.screen(containingMouse: NSEvent.mouseLocation) else { return }
        panel.setFrame(screen.frame, display: true)

        // Take the keyboard while switching (see the type comment).
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            previousApp = front
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installLocalMonitor()
    }

    /// While Plinth is active, keys arrive as ordinary app events.
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
        switch event.keyCode {
        case 53: handle(.escape)
        case 123: handle(.left)
        case 124: handle(.right)
        case 36, 76: handle(.enter)
        default: break
        }
        return true // nothing else reaches any app while switching
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let hosting = FirstMouseHostingView(rootView: SwitcherView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }
}
