import AppKit
import SwiftUI

/// What the window list shows for one Dock icon. Built by its source (the Dock)
/// each time the list is drawn, so it is always current.
struct WindowListItem {
    let bundleID: String
    let name: String
    /// The app's windows, most recently used first; all Spaces, minimized included.
    let windows: [WindowSnapshot]
    let isNotResponding: Bool
}

/// The screen edge the Dock sits on; the list opens away from it.
enum DockEdge {
    case bottom, left, right
}

/// Where the window list gets its content and its position.
@MainActor
protocol WindowListSource: AnyObject {
    /// nil when there is nothing to list (the app has no windows).
    func windowListItem(for key: String) -> WindowListItem?
    /// The icon the list belongs to, in screen (Cocoa) coordinates.
    func anchor(for key: String) -> NSRect?
    var dockEdge: DockEdge { get }
}

/// One window in the list, ready to draw.
struct WindowListRow: Identifiable {
    let id: CGWindowID
    let title: String
    let icon: NSImage?
    let minimap: CGRect?
    let isMinimized: Bool
    let isOnOtherSpace: Bool
    let isActive: Bool
    /// The app's colour, from its icon; colours the mini-map.
    let tint: Color
    /// Browser tabs of this window, once read (empty for other apps).
    let tabs: [BrowserTab]
}

/// State the views draw. Hover state lives here, not in SwiftUI's @State: @State
/// is a macro, and the Command Line Tools cannot expand macros.
@MainActor
final class WindowListModel: ObservableObject {
    @Published var title = ""
    @Published var rows: [WindowListRow] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var showsPreviews = false
    @Published var hoveredRow: CGWindowID?
    @Published var hoveredTab: String?
    /// The window whose picture the peek pane shows (previews on, with tabs).
    @Published var peekWindow: CGWindowID?
    /// The mouse is on the peek pane's picture.
    @Published var hoveringPeek = false
    /// Windows whose long tab list is shown in full.
    @Published var expanded = Set<CGWindowID>()

    var hasTabs: Bool { rows.contains { $0.tabs.count > 1 } }
    var usesCards: Bool { WindowListLayout.usesCards(rows: rows, previews: showsPreviews) }

    func setHovered(_ id: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredRow = id
            peekWindow = id
        } else if hoveredRow == id {
            hoveredRow = nil
        }
    }

    func setHoveredTab(_ id: String, window: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredTab = id
            peekWindow = window
        } else if hoveredTab == id {
            hoveredTab = nil
        }
    }
}

/// Sizes. The panel's size is computed here, not by SwiftUI, so it is known
/// before anything is drawn and the list never jumps.
enum WindowListLayout {
    static let listWidth: CGFloat = 320
    static let tabListWidth: CGFloat = 400
    static let rowHeight: CGFloat = 48
    static let maxVisibleRows = 10
    static let cardWidth: CGFloat = 212
    static let cardHeight: CGFloat = 156
    static let tabRowHeight: CGFloat = 28
    static let tabListPadding: CGFloat = 6
    /// Longer tab lists are folded behind "Show all N tabs".
    static let foldedTabs = 8
    static let maxListHeight: CGFloat = 600
    /// The picture under the tab list when previews are on.
    static let peekHeight: CGFloat = 230

    /// The tabs listed under a window, and how many are folded away.
    static func visibleTabs(of row: WindowListRow, expanded: Bool) -> (tabs: [BrowserTab], hidden: Int) {
        guard row.tabs.count > 1 else { return ([], 0) }
        if expanded || row.tabs.count <= foldedTabs { return (row.tabs, 0) }
        var shown = Array(row.tabs.prefix(foldedTabs - 1))
        // The tab you are on is always listed.
        if let selected = row.tabs.first(where: \.isSelected), !shown.contains(where: { $0.id == selected.id }) {
            shown.append(selected)
        }
        return (shown, row.tabs.count - shown.count)
    }

    /// Picture cards side by side, while they fit (five); otherwise the list,
    /// with one picture underneath.
    static let maxCards = 5

    static func usesCards(rows: [WindowListRow], previews: Bool) -> Bool {
        previews && rows.count <= maxCards && !rows.contains { $0.tabs.count > 1 }
    }

    static func size(rows: [WindowListRow], expanded: Set<CGWindowID>, previews: Bool) -> NSSize {
        if rows.isEmpty {
            return NSSize(width: 220, height: 44)
        }
        let hasTabs = rows.contains { $0.tabs.count > 1 }
        if usesCards(rows: rows, previews: previews) {
            let columns = rows.count
            return NSSize(width: CGFloat(columns) * cardWidth + 16, height: 36 + cardHeight + 12)
        }
        var height: CGFloat = 36 + 10
        for row in rows.prefix(maxVisibleRows) {
            height += rowHeight
            let (tabs, hidden) = visibleTabs(of: row, expanded: expanded.contains(row.id))
            guard !tabs.isEmpty else { continue }
            height += CGFloat(tabs.count + (hidden > 0 ? 1 : 0)) * tabRowHeight + tabListPadding
        }
        if previews {
            // The tab list on top, one picture of the window under the mouse below it.
            return NSSize(width: tabListWidth, height: min(height, maxListHeight - peekHeight) + peekHeight + 6)
        }
        return NSSize(width: hasTabs ? tabListWidth : listWidth, height: min(height, maxListHeight))
    }
}

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

    var isVisible: Bool { panel?.isVisible == true }
    /// The popup's frame on screen while it is visible.
    var visibleFrame: NSRect? { isVisible ? panel?.frame : nil }

    init(registry: WindowRegistry) {
        self.registry = registry
        // Windows change (titles, minimizing, closing) while the list is open.
        registry.addObserver { [weak self] in self?.refreshIfVisible() }
    }

    // MARK: - Hover choreography

    func itemEntered(_ key: String) {
        hideTask?.cancel()
        showTask?.cancel()
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
        scheduleHide()
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
        showTask?.cancel()
        hideTask?.cancel()
        previewTasks.forEach { $0.cancel() }
        previewTasks = []
        previewIDs = []
        shownSignature = []
        panel?.orderOut(nil)
        currentKey = nil
        model.thumbnails = [:]
    }

    func refreshIfVisible() {
        guard isVisible, let currentKey else { return }
        present(currentKey)
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
        // Nothing to list (say, the mouse moved on to an app with no windows):
        // the previous app's list must not stay up.
        guard let source, let item = source.windowListItem(for: key), let anchor = source.anchor(for: key) else {
            hideNow()
            return
        }
        let changedItem = currentKey != key
        currentKey = key
        if changedItem {
            model.expanded = []
            model.peekWindow = nil
            model.hoveringPeek = false
            model.thumbnails = [:]
        }

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
                tabs: TabStore.shared.tabs(of: window.id) ?? []
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
        if previews { loadPreviews(for: Array(item.windows.prefix(8))) }
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

    /// Shows the pictures memory already has at once, then captures fresh ones
    /// side by side — not one after another.
    private func loadPreviews(for windows: [WindowSnapshot]) {
        let ids = windows.map(\.id)
        guard ids != previewIDs else { return }
        previewTasks.forEach { $0.cancel() }
        previewIDs = ids
        for id in ids where model.thumbnails[id] == nil {
            if let cached = PreviewProvider.shared.cachedThumbnail(for: id) { model.thumbnails[id] = cached }
        }
        previewTasks = windows.map { window in
            Task { @MainActor [weak self] in
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The list may have closed while capturing: drop the image then.
                guard !Task.isCancelled, let self, self.isVisible, let image else { return }
                self.model.thumbnails[window.id] = image
            }
        }
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
