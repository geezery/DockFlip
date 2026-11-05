import AppKit
import SwiftUI

/// The list of an app's windows that opens when the mouse rests on its Dock
/// icon — the Windows taskbar's hover list. Click a window (or tab) to bring it
/// forward, × to close it.
///
/// Timing, as on Windows: opens 0.25 s after the mouse arrives (no flashing while
/// it passes over the Dock), closes 0.3 s after it leaves (time to reach the list).
@MainActor
final class WindowListPopup {
    private let registry: WindowRegistry
    weak var source: WindowListSource?

    private let model = WindowListModel()
    private var panel: NSPanel?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    /// The icon shown, by its source's key.
    private var currentKey: String?
    /// What the open list shows, to skip redrawing when a change elsewhere
    /// (another app's window) leaves it as it is.
    private var shownSignature: [String] = []
    private var previewTasks: [Task<Void, Never>] = []
    /// Windows whose pictures are loading or loaded, so a redraw does not start them over.
    private var previewIDs: [CGWindowID] = []
    /// Windows past the first batch, captured one by one as the mouse reaches them.
    private var hoverPreviewIDs = Set<CGWindowID>()
    private var hoverPreviewTasks: [Task<Void, Never>] = []
    /// The open list's windows, for capturing the hovered one.
    private var shownWindows: [WindowSnapshot] = []
    /// The hovered icon whose windows had not arrived when its list wanted to open.
    private var waiting = WindowListWait()

    var isVisible: Bool { panel?.isVisible == true }
    /// The popup's frame on screen while it is visible.
    var visibleFrame: NSRect? { isVisible ? panel?.frame : nil }
    /// The icon whose list is on screen, by its source's key.
    var shownKey: String? { isVisible ? currentKey : nil }

    init(registry: WindowRegistry) {
        self.registry = registry
        // Windows change (titles, minimizing, closing) while the list is open.
        registry.addObserver { [weak self] in self?.refreshIfVisible() }
        model.peekChanged = { [weak self] id in self?.loadHoveredPreview(id) }
    }

    // MARK: - Hover choreography

    func itemEntered(_ key: String) {
        hideTask?.cancel()
        showTask?.cancel()
        waiting.stop()
        // The window list is the slow part of a first picture: fetch it while the list waits to open.
        PreviewProvider.shared.prefetchWindowList()
        if isVisible {
            present(key)
            return
        }
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.present(key)
        }
    }

    func itemExited() {
        showTask?.cancel()
        waiting.stop()
        scheduleHide()
    }

    /// A press on a Dock icon: whatever it opens, no list pops up under the mouse
    /// for it until the mouse rests on an icon again.
    func dockPressed() {
        waiting.stop()
    }

    /// The mouse came back onto the icon from the list: keep the list.
    func cancelHide() {
        hideTask?.cancel()
    }

    /// From the hosting view's tracking area.
    func popupHover(_ inside: Bool) {
        if inside {
            hideTask?.cancel()
        } else {
            scheduleHide()
        }
    }

    func hideNow() {
        waiting.stop()
        hidePanel()
    }

    /// Hides the list but keeps waiting for the hovered icon's windows.
    private func hidePanel() {
        showTask?.cancel()
        hideTask?.cancel()
        previewTasks.forEach { $0.cancel() }
        previewTasks = []
        previewIDs = []
        cancelHoverPreviews()
        shownWindows = []
        shownSignature = []
        panel?.orderOut(nil)
        currentKey = nil
        model.thumbnails = [:]
    }

    /// Redraws the open list, or opens the waiting icon's list once its windows
    /// arrived (window reads run off the main thread, so they can come after the
    /// hover delay).
    func refreshIfVisible() {
        if isVisible, let currentKey {
            present(currentKey)
        } else if let key = waiting.keyToOpen(isVisible: isVisible, hasWindows: { self.source?.windowListItem(for: $0) != nil }) {
            present(key)
        }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.hideNow()
        }
    }

    // MARK: - Content

    private func present(_ key: String) {
        Perf.shared.measure("windowList.present") { presentUnmeasured(key) }
    }

    private func presentUnmeasured(_ key: String) {
        // The mouse is no longer on this icon.
        guard let source, let anchor = source.anchor(for: key) else {
            hideNow()
            return
        }
        // Nothing to list (say, the mouse moved on to an app with no windows):
        // the previous app's list must not stay up. The app may still be
        // answering, so its list opens if its windows arrive while the mouse stays.
        guard let item = source.windowListItem(for: key) else {
            hidePanel()
            waiting.nothingToList(key)
            return
        }
        waiting.stop()
        let changedItem = currentKey != key
        currentKey = key
        if changedItem {
            cancelHoverPreviews()
            model.startNewList()
        }
        shownWindows = item.windows

        let activeID = registry.activeWindowID()
        let title = item.isNotResponding ? "\(item.name) — \(L("Not responding"))" : item.name
        let rows = item.windows.map { window -> WindowListRow in
            WindowListRow(
                id: window.id,
                title: window.title.isEmpty ? window.appName : window.title,
                icon: window.icon,
                minimap: WindowAppearance.placement(of: window.frame)?.minimap,
                isMinimized: window.isMinimized,
                isOnOtherSpace: window.isOnOtherSpace,
                isActive: window.id == activeID,
                tint: WindowAppearance.tint(of: window),
                tabs: TabStore.shared.tabs(of: window.id) ?? [],
                windowSize: window.frame.size,
                neverPictured: PreviewProvider.neverPictured(window)
            )
        }

        // Window changes arrive for every app; when nothing this list shows
        // changed, there is nothing to redraw or resize.
        let signature = rows.map { row in
            "\(row.id)|\(row.title)|\(row.isMinimized)|\(row.isActive)|\(row.isOnOtherSpace)|\(row.tabs.map(\.fullTitle))"
        } + ["\(model.expanded.sorted())", title]
        if !changedItem, isVisible, signature == shownSignature { return }
        shownSignature = signature

        model.title = title
        let tabsArrived = !changedItem && !model.hasTabs && rows.contains { $0.tabs.count > 1 }
        if tabsArrived {
            // Tabs slide in under their windows.
            withAnimation(.snappy(duration: 0.28)) { model.rows = rows }
        } else {
            model.rows = rows
        }
        if BrowserTabs.hasTabs(item.bundleID) {
            let windows = item.windows.compactMap { window in
                registry.axElement(for: window.id).map { (id: window.id, element: $0) }
            }
            TabStore.shared.load(windows) { [weak self] in self?.refreshIfVisible() }
        }
        let previews = PreviewProvider.shared.isAvailable
        model.showsPreviews = previews

        showPanel(size: WindowListLayout.size(rows: rows, expanded: model.expanded, previews: previews), at: anchor, edge: source.dockEdge)
        if previews {
            let first = Set(WindowListPreviews.firstBatch(item.windows.map(\.id)))
            loadPreviews(for: item.windows.filter { first.contains($0.id) })
        }
    }

    /// Next to the icon on the side away from the Dock's edge (above a bottom
    /// Dock, beside a side Dock), centred on the icon, kept inside its screen.
    private func showPanel(size: NSSize, at anchor: NSRect, edge: DockEdge) {
        let center = NSPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(center, $0.frame, false) }?.frame ?? anchor
        func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat { min(max(value, low), max(low, high)) }
        let origin: NSPoint
        switch edge {
        case .bottom:
            origin = NSPoint(x: clamp(anchor.midX - size.width / 2, screen.minX + 8, screen.maxX - size.width - 8),
                             y: anchor.maxY + 6)
        case .left:
            origin = NSPoint(x: anchor.maxX + 6,
                             y: clamp(anchor.midY - size.height / 2, screen.minY + 8, screen.maxY - size.height - 8))
        case .right:
            origin = NSPoint(x: anchor.minX - 6 - size.width,
                             y: clamp(anchor.midY - size.height / 2, screen.minY + 8, screen.maxY - size.height - 8))
        }
        let frame = NSRect(x: origin.x.rounded(), y: origin.y.rounded(), width: size.width, height: size.height)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// Shows the pictures memory already has at once, then captures the windows
    /// whose picture is out of date (`PreviewProvider`, which also limits how many
    /// run together).
    private func loadPreviews(for windows: [WindowSnapshot]) {
        let ids = windows.map(\.id)
        guard ids != previewIDs else { return }
        previewTasks.forEach { $0.cancel() }
        previewIDs = ids
        // Cards are small; the peek pane shows one window large.
        let size = model.usesCards ? PreviewProvider.cardPixelSize : Int(PreviewProvider.maxPixelWidth)
        previewTasks = windows.map { window in
            Task { @MainActor [weak self] in
                await PreviewProvider.shared.loadPicture(of: window, maxPixelSize: size) { image in
                    // The list may have closed meanwhile: drop the image then.
                    guard let self, self.isVisible else { return }
                    self.model.thumbnails[window.id] = image
                }
            }
        }
    }

    /// The peek pane turned to a window the first batch left out (the 9th
    /// onwards): load just that one, ahead of any other capture.
    private func loadHoveredPreview(_ id: CGWindowID) {
        guard isVisible, model.showsPreviews,
              let target = WindowListPreviews.onHover(id, listed: shownWindows.map(\.id),
                                                      requested: Set(previewIDs).union(hoverPreviewIDs),
                                                      shown: Set(model.thumbnails.keys)),
              let window = shownWindows.first(where: { $0.id == target }) else { return }
        hoverPreviewIDs.insert(target)
        hoverPreviewTasks.append(Task { @MainActor [weak self] in
            await PreviewProvider.shared.loadPicture(of: window, urgent: true) { image in
                guard let self, self.isVisible else { return }
                self.model.thumbnails[target] = image
            }
        })
    }

    private func cancelHoverPreviews() {
        hoverPreviewTasks.forEach { $0.cancel() }
        hoverPreviewTasks = []
        hoverPreviewIDs = []
    }

    private func makePanel() -> NSPanel {
        let panel = Panels.make(
            level: Panels.aboveDock,
            behavior: [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone],
            shadow: true
        )
        let hosting = WindowListHostingView(rootView: WindowListView(model: model, popup: self))
        hosting.sizingOptions = [] // the panel's frame decides the size, not SwiftUI
        hosting.popup = self
        panel.contentView = hosting
        return panel
    }

    // MARK: - Actions from the views

    func pick(_ id: CGWindowID) {
        hideNow()
        registry.focus(id)
    }

    func close(_ id: CGWindowID) {
        registry.close(id)
    }

    func pickTab(_ tab: BrowserTab) {
        hideNow()
        BrowserTabs.select(tab)
        TabStore.shared.forget(tab.windowID)
        registry.focus(tab.windowID)
    }

    func toggleExpanded(_ id: CGWindowID) {
        if model.expanded.contains(id) {
            model.expanded.remove(id)
        } else {
            model.expanded.insert(id)
        }
        refreshIfVisible()
    }
}

/// Keeps the list open while the mouse is over it: a tracking area that works
/// even though DockFlip is never the active app.
final class WindowListHostingView: NSHostingView<WindowListView> {
    weak var popup: WindowListPopup?
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        popup?.popupHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        popup?.popupHover(false)
    }
}
