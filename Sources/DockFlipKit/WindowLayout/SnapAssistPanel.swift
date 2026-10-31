import AppKit
import SwiftUI

/// What the Snap Assist view draws; `SnapAssistPanel` changes it, the view only reads it.
@MainActor
final class SnapAssistModel: ObservableObject {
    @Published var items: [SwitcherItem] = []
    @Published var selection = 0
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var grid = SnapAssistGrid(region: .zero)
    var onPick: ((Int) -> Void)?
}

/// Windows 11 Snap Assist: after a window snaps to a half or a quarter, the region
/// left beside it shows the other windows as cards. Clicking one, or choosing it
/// with the arrows and Return, puts it in that region; Esc, a click anywhere else
/// or the next snap closes the cards. `SnapController` decides when; the rules are
/// `SnapAssist` and `SnapAssistGrid`.
///
/// Like the ⌘Tab switcher (`SwitcherPanel`), the panel is non-activating and made
/// key without activating DockFlip: the app whose window just snapped stays the
/// active app, and the arrows and Return still reach the cards.
@MainActor
final class SnapAssistPanel {
    private let model = SnapAssistModel()
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var resignKeyToken: NSObjectProtocol?
    private var previewTasks: [Task<Void, Never>] = []
    /// The region being offered, in AX space; nil while nothing is shown.
    private var region: CGRect?

    /// The window picked and the region (AX space) it should fill.
    var onPick: ((CGWindowID, CGRect) -> Void)?

    var isShown: Bool { region != nil }

    init() {
        model.onPick = { [weak self] index in self?.pick(at: index) }
    }

    /// Shows `windows` (most recently used first) as cards over `region` (AX space).
    /// Takes as many as fit (`capacity(for:)`).
    func show(_ windows: [WindowSnapshot], over region: CGRect) {
        dismiss()
        let grid = SnapAssistGrid(region: region.size)
        let shown = Array(windows.prefix(grid.capacity))
        guard !shown.isEmpty else { return }
        let previews = PreviewProvider.shared.isAvailable
        model.grid = grid
        model.items = shown.map { SwitcherItem(window: $0, previews: previews) }
        model.selection = 0
        model.thumbnails = [:]
        self.region = region

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let frame = Geometry.cocoaRect(fromAX: region, primaryHeight: DisplayLayout.primaryHeight)
        panel.setFrame(frame.insetBy(dx: 6, dy: 6), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installLocalMonitor()
        loadPreviews(of: shown, enabled: previews)
        Log.snap.info("Snap Assist offers \(shown.count, privacy: .public) windows")
    }

    /// How many cards fit in `region` (AX space).
    static func capacity(for region: CGRect) -> Int {
        SnapAssistGrid(region: region.size).capacity
    }

    func dismiss() {
        guard isShown else { return }
        region = nil
        previewTasks.forEach { $0.cancel() }
        previewTasks = []
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        panel?.orderOut(nil)
        model.items = []
        model.thumbnails = [:]
    }

    private func pick(at index: Int) {
        guard let region, model.items.indices.contains(index) else { return }
        let id = model.items[index].windowID
        dismiss()
        onPick?(id, region)
    }

    /// Pictures memory holds appear with the cards; the rest are captured side by
    /// side and drop in as they come. Only while thumbnails are on.
    private func loadPreviews(of windows: [WindowSnapshot], enabled: Bool) {
        guard enabled else { return }
        for window in windows where !PreviewProvider.neverPictured(window) {
            if let cached = PreviewProvider.shared.cachedThumbnail(for: window.id) {
                model.thumbnails[window.id] = cached
            }
        }
        previewTasks = windows.map { window in
            Task { @MainActor [weak self] in
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The cards may have closed while capturing: drop the image then.
                guard !Task.isCancelled, let self, self.isShown, let image else { return }
                self.model.thumbnails[window.id] = image
            }
        }
    }

    /// The panel is key, so keys arrive here as ordinary app events. Shortcuts
    /// (⌃, ⌥, ⌘) go on: a ⌃⌥ arrow is the next snap, and Carbon delivers it.
    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let swallow: Bool = MainActor.assumeIsolated { self?.handleKey(event) ?? false }
            return swallow ? nil : event
        }
    }

    /// Returns true when the key must not reach anything else.
    private func handleKey(_ event: NSEvent) -> Bool {
        guard isShown, event.window === panel else { return false }
        let shortcut = !event.modifierFlags.intersection([.control, .option, .command]).isEmpty
        guard let key = SnapAssistKey.from(keyCode: UInt32(event.keyCode), hasShortcutModifiers: shortcut) else {
            // Typing goes nowhere while the cards are up; swallowed, so the panel does not beep.
            return !shortcut
        }
        switch key {
        case .move(let direction):
            model.selection = model.grid.move(direction, from: model.selection, count: model.items.count)
        case .pick:
            pick(at: model.selection)
        case .dismiss:
            dismiss()
        }
        return true
    }

    /// Losing key status means the user went elsewhere (⌘Tab, a window that took
    /// the keyboard): the offer is over, as on Windows. Checked on the next turn,
    /// as `dismiss()` itself makes the panel resign.
    private func observeResignKey(of panel: NSPanel) {
        resignKeyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isShown, self.panel?.isKeyWindow == false else { return }
                self.dismiss()
            }
        }
    }

    private func makePanel() -> NSPanel {
        // Above normal windows on the current Space; takes the keyboard.
        let panel = Panels.make(
            level: .floating,
            behavior: [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle],
            keyable: true,
            shadow: true
        )
        let hosting = FirstMouseHostingView(rootView: SnapAssistView(model: model))
        hosting.sizingOptions = [] // the region decides the size, not SwiftUI
        panel.contentView = hosting
        observeResignKey(of: panel)
        return panel
    }
}
