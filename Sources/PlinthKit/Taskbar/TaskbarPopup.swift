import AppKit
import SwiftUI

struct PopupRow: Identifiable {
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
    var tabs: [BrowserTab] = []
}

@MainActor
final class PopupModel: ObservableObject {
    @Published var title = ""
    @Published var rows: [PopupRow] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
    @Published var showsPreviews = false
    /// Row under the mouse. Kept here, not in @State: @State is a macro that the
    /// Command Line Tools cannot expand.
    @Published var hoveredRow: CGWindowID?
    @Published var hoveredTab: String?
    /// The window whose picture the preview pane shows (with tabs and previews on).
    @Published var peekWindow: CGWindowID?

    var hasTabs: Bool { rows.contains { $0.tabs.count > 1 } }
    /// Windows whose long tab list is shown in full.
    @Published var expanded = Set<CGWindowID>()

    func setHoveredTab(_ id: String, window: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredTab = id
            peekWindow = window
        } else if hoveredTab == id {
            hoveredTab = nil
        }
    }

    func setHovered(_ id: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredRow = id
            peekWindow = id
        } else if hoveredRow == id {
            hoveredRow = nil
        }
    }
}

enum PopupLayout {
    static let listWidth: CGFloat = 320
    static let rowHeight: CGFloat = 48
    static let maxVisibleRows = 10
    static let cardWidth: CGFloat = 212
    static let cardHeight: CGFloat = 156

    static let tabListWidth: CGFloat = 400
    static let tabRowHeight: CGFloat = 28
    static let tabListPadding: CGFloat = 6
    /// Longer tab lists are folded behind "Show all N tabs".
    static let foldedTabs = 8
    static let maxListHeight: CGFloat = 600

    /// The tabs listed under a window, and how many are folded away.
    static func visibleTabs(of row: PopupRow, expanded: Bool) -> (tabs: [BrowserTab], hidden: Int) {
        guard row.tabs.count > 1 else { return ([], 0) }
        if expanded || row.tabs.count <= foldedTabs { return (row.tabs, 0) }
        var shown = Array(row.tabs.prefix(foldedTabs - 1))
        // The tab you are on is always listed.
        if let selected = row.tabs.first(where: \.isSelected), !shown.contains(where: { $0.id == selected.id }) {
            shown.append(selected)
        }
        return (shown, row.tabs.count - shown.count)
    }

    /// The picture under the tab list when previews are on.
    static let peekHeight: CGFloat = 230

    static func size(rows: [PopupRow], expanded: Set<CGWindowID>, previews: Bool) -> NSSize {
        if rows.isEmpty {
            return NSSize(width: 220, height: 44)
        }
        let hasTabs = rows.contains { $0.tabs.count > 1 }
        if previews && !hasTabs {
            let columns = min(rows.count, 5)
            return NSSize(width: CGFloat(columns) * cardWidth + 16, height: 36 + cardHeight + 12)
        }
        var height: CGFloat = 36 + 10
        var hasTabs = false
        for row in rows.prefix(maxVisibleRows) {
            height += rowHeight
            let (tabs, hidden) = visibleTabs(of: row, expanded: expanded.contains(row.id))
            guard !tabs.isEmpty else { continue }
            hasTabs = true
            height += CGFloat(tabs.count + (hidden > 0 ? 1 : 0)) * tabRowHeight + tabListPadding
        }
        if previews {
            // The tab list on top, one picture of the window under the mouse below it.
            return NSSize(width: tabListWidth, height: min(height, maxListHeight - peekHeight) + peekHeight + 6)
        }
        return NSSize(width: hasTabs ? tabListWidth : listWidth, height: min(height, maxListHeight))
    }
}

/// What the hover popup shows windows for: Plinth's own taskbar, or the real Dock.
@MainActor
protocol PopupSource: AnyObject {
    func item(_ itemID: String, on displayID: CGDirectDisplayID) -> TaskbarItem?
    /// The button (or Dock icon) in screen coordinates.
    func anchorRect(for itemID: String, on displayID: CGDirectDisplayID) -> NSRect?
}

/// The window list (or thumbnails) that opens when the mouse rests on a taskbar button.
@MainActor
final class TaskbarPopup {
    private let registry: WindowRegistry
    weak var source: PopupSource?

    private let model = PopupModel()
    private var panel: NSPanel?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var previewTasks: [Task<Void, Never>] = []
    /// Windows whose pictures are loading or loaded, so a refresh of the list
    /// (titles change all the time) does not start them over.
    private var previewIDs: [CGWindowID] = []
    private var current: (itemID: String, displayID: CGDirectDisplayID)?

    var isVisible: Bool { panel?.isVisible == true }
    /// The popup's frame on screen while it is visible.
    var visibleFrame: NSRect? { isVisible ? panel?.frame : nil }

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    // MARK: Hover choreography

    func itemEntered(_ itemID: String, on displayID: CGDirectDisplayID) {
        hideTask?.cancel()
        showTask?.cancel()
        if isVisible {
            present(itemID, on: displayID)
            return
        }
        showTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.present(itemID, on: displayID)
        }
    }

    func itemExited() {
        showTask?.cancel()
        scheduleHide()
    }

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
        panel?.orderOut(nil)
        current = nil
        model.thumbnails = [:]
    }

    func refreshIfVisible() {
        guard isVisible, let current else { return }
        if source?.item(current.itemID, on: current.displayID) == nil {
            hideNow()
        } else {
            present(current.itemID, on: current.displayID)
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

    // MARK: Content

    private func present(_ itemID: String, on displayID: CGDirectDisplayID) {
        Perf.shared.measure("taskbar.popup") { presentUnmeasured(itemID, on: displayID) }
    }

    private func presentUnmeasured(_ itemID: String, on displayID: CGDirectDisplayID) {
        // Nothing to list (say, the mouse moved on to an app with no windows):
        // the previous app's list must not stay up.
        guard let source, let item = source.item(itemID, on: displayID),
              let anchor = source.anchorRect(for: itemID, on: displayID) else {
            hideNow()
            return
        }
        let changedItem = current?.itemID != itemID
        current = (itemID, displayID)
        if changedItem {
            model.expanded = []
            model.peekWindow = nil
        }

        let screens = NSScreen.screens
        let axScreens = screens.map { DisplayLayout.axFrame(of: $0) }
        let activeID = registry.activeWindowID()
        let onScreen = Set(WindowRegistry.onScreenWindowIDs())
        model.title = item.isNotResponding ? "\(item.name) — \(L("Not responding"))" : item.name
        let hadTabs = model.rows.contains { !$0.tabs.isEmpty }
        let rows = item.windowIDs.compactMap { id -> PopupRow? in
            guard let window = registry.window(id) else { return nil }
            let index = Geometry.bestScreenIndex(for: window.frame, screens: axScreens)
            return PopupRow(
                id: id,
                title: window.title.isEmpty ? window.appName : window.title,
                icon: window.icon,
                minimap: index.map { Geometry.normalized(window.frame, in: axScreens[$0]) },
                isMinimized: window.isMinimized,
                isOnOtherSpace: !window.isMinimized && !window.isAppHidden && !onScreen.contains(id),
                isActive: id == activeID,
                tint: IconTint.color(for: window.icon, key: window.bundleID ?? window.appName),
                tabs: TabStore.shared.tabs(of: id) ?? []
            )
        }
        // Tabs sliding in under their windows when they arrive.
        if !changedItem, !hadTabs, rows.contains(where: { !$0.tabs.isEmpty }) {
            withAnimation(.snappy(duration: 0.28)) { model.rows = rows }
        } else {
            model.rows = rows
        }
        if BrowserTabs.hasTabs(item.bundleID) {
            let windows = item.windowIDs.compactMap { id in registry.axElement(for: id).map { (id: id, element: $0) } }
            TabStore.shared.load(windows) { [weak self] in self?.refreshIfVisible() }
        }
        let previews = PreviewProvider.shared.isAvailable && !model.rows.isEmpty
        model.showsPreviews = previews
        if changedItem { model.thumbnails = [:] }

        let size = PopupLayout.size(rows: model.rows, expanded: model.expanded, previews: previews)
        let screenFrame = screens.first { NSMouseInRect(NSPoint(x: anchor.midX, y: anchor.midY), $0.frame, false) }?.frame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let frame = NSRect(x: x.rounded(), y: (anchor.maxY + 6).rounded(), width: size.width, height: size.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        if previews { loadPreviews(for: Array(item.windowIDs.prefix(8))) }
    }

    /// Shows the pictures memory already has at once, then captures fresh ones
    /// side by side — not one after another.
    private func loadPreviews(for ids: [CGWindowID]) {
        guard ids != previewIDs else { return }
        previewTasks.forEach { $0.cancel() }
        previewIDs = ids
        for id in ids where model.thumbnails[id] == nil {
            if let cached = PreviewProvider.shared.cachedThumbnail(for: id) { model.thumbnails[id] = cached }
        }
        previewTasks = ids.map { id in
            Task { @MainActor [weak self] in
                guard let self, let window = self.registry.window(id) else { return }
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The popup may have closed while capturing: drop the image then.
                guard !Task.isCancelled, self.isVisible, let image else { return }
                self.model.thumbnails[id] = image
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = PanelFactory.make(level: PanelFactory.popupLevel, shadow: true)
        let hosting = PopupHostingView(rootView: PopupView(model: model, popup: self))
        hosting.sizingOptions = [] // the panel's frame decides the size, not SwiftUI
        hosting.popup = self
        panel.contentView = hosting
        return panel
    }

    // MARK: Actions from the view

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

struct PopupView: View {
    @ObservedObject var model: PopupModel
    let popup: TaskbarPopup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: model.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: model.rows.isEmpty ? 44 : 36, alignment: .center)

            if !model.rows.isEmpty {
                if model.showsPreviews && !model.hasTabs {
                    HStack(spacing: 4) {
                        ForEach(model.rows.prefix(5)) { row in
                            PopupCard(row: row, thumbnail: model.thumbnails[row.id], model: model, popup: popup)
                        }
                    }
                    .padding(.horizontal, 6)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            ForEach(model.rows) { row in
                                PopupListRow(row: row, model: model, popup: popup)
                                let visible = PopupLayout.visibleTabs(of: row, expanded: model.expanded.contains(row.id))
                                if !visible.tabs.isEmpty {
                                    PopupTabList(row: row, tabs: visible.tabs, hidden: visible.hidden, model: model, popup: popup)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .scrollIndicators(.never)
                    if model.showsPreviews {
                        PeekPane(model: model)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Pictures need a calm, nearly solid backdrop; the lighter glass suits the plain list.
        .background(
            model.showsPreviews ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(.regularMaterial),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Keeps the popup open while the mouse is over it (tracking area active even
/// though Plinth is never the active app).
final class PopupHostingView: NSHostingView<PopupView> {
    weak var popup: TaskbarPopup?
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

struct PopupListRow: View {
    let row: PopupRow
    @ObservedObject var model: PopupModel
    let popup: TaskbarPopup

    private var hovering: Bool { model.hoveredRow == row.id }

    var body: some View {
        HStack(spacing: 10) {
            Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                .frame(width: 52, height: 33)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: row.isActive ? 1.5 : 0)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.system(size: 13, weight: row.isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.isActive {
                    // The window in front: said in words too, not only with weight.
                    Text(verbatim: row.tabs.count > 1 ? L("Active window") + " · " + TabSummary.text(for: row.tabs) : L("Active window"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                } else if row.isMinimized {
                    Text("Minimized").font(.system(size: 11)).foregroundStyle(.secondary)
                } else if row.tabs.count > 1 {
                    Text(verbatim: TabSummary.text(for: row.tabs))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if row.isOnOtherSpace {
                    Text("On another desktop").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Button {
                popup.close(row.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .accessibilityLabel(Text("Close window"))
        }
        .padding(.horizontal, 8)
        .frame(height: PopupLayout.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity((row.isActive ? 0.14 : 0) + (hovering ? 0.10 : 0)))
        )
        // Windows 11's active marker: a short accent pill at the edge.
        .overlay(alignment: .leading) {
            if row.isActive {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3, height: 20)
                    .offset(x: 1)
            }
        }
        .contentShape(Rectangle())
        .onHover { model.setHovered(row.id, $0) }
        .onTapGesture { popup.pick(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct PopupCard: View {
    let row: PopupRow
    let thumbnail: NSImage?
    @ObservedObject var model: PopupModel
    let popup: TaskbarPopup

    private var hovering: Bool { model.hoveredRow == row.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                AppIconView(icon: row.icon, size: 16)
                Text(verbatim: row.title)
                    .font(.system(size: 12, weight: row.isActive ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if row.tabs.count > 1 {
                    Text(verbatim: "\(row.tabs.count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.1), in: Capsule())
                        .help(Text(verbatim: TabSummary.text(for: row.tabs)))
                }
                Button {
                    popup.close(row.id)
                } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0.35)
                .accessibilityLabel(Text("Close window"))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06))
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                } else {
                    Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                }
            }
            .frame(width: 188, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(6)
        .frame(width: PopupLayout.cardWidth - 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity((row.isActive ? 0.14 : 0) + (hovering ? 0.10 : 0)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: row.isActive ? 2 : 0)
        )
        .contentShape(Rectangle())
        .onHover { model.setHovered(row.id, $0) }
        .onTapGesture { popup.pick(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// "15 tabs · Gmail, YouTube, Teams +3": how many tabs, and the sites most of them are on.
enum TabSummary {
    static func text(for tabs: [BrowserTab]) -> String {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        for (index, tab) in tabs.enumerated() {
            guard let site = tab.site else { continue }
            counts[site, default: 0] += 1
            if firstSeen[site] == nil { firstSeen[site] = index }
        }
        let sites = counts.keys.sorted {
            counts[$0]! != counts[$1]! ? counts[$0]! > counts[$1]! : firstSeen[$0]! < firstSeen[$1]!
        }
        var text = String(format: L("%ld tabs"), tabs.count)
        if !sites.isEmpty {
            text += " · " + sites.prefix(3).joined(separator: ", ")
            if sites.count > 3 { text += " +\(sites.count - 3)" }
        }
        return text
    }
}

/// A stable colour per site, so the same site always wears the same chip.
enum SiteColor {
    static func hue(for site: String) -> Double {
        var hash: UInt32 = 2_166_136_261
        for byte in site.lowercased().utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Double(hash % 360) / 360
    }
}

/// The tabs of one browser window, hanging under it like branches.
struct PopupTabList: View {
    let row: PopupRow
    let tabs: [BrowserTab]
    let hidden: Int
    @ObservedObject var model: PopupModel
    let popup: TaskbarPopup

    var body: some View {
        let titles = Dictionary(grouping: row.tabs, by: \.fullTitle).filter { $0.value.count > 1 }
        VStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { position, tab in
                // A later copy of a tab already open in this window.
                let isDuplicate = titles[tab.fullTitle].map { $0.first?.id != tab.id } ?? false
                PopupTabRow(
                    tab: tab,
                    isLast: position == tabs.count - 1 && hidden == 0,
                    isDuplicate: isDuplicate,
                    tint: row.tint,
                    model: model,
                    popup: popup
                )
            }
            if hidden > 0 {
                Button {
                    popup.toggleExpanded(row.id)
                } label: {
                    HStack(spacing: 8) {
                        TreeBranch(isLast: true)
                            .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                            .frame(width: 14)
                        Text(String(format: L("Show all %ld tabs"), row.tabs.count))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                    }
                    .padding(.leading, 30)
                    .frame(height: PopupLayout.tabRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, PopupLayout.tabListPadding)
    }
}

struct PopupTabRow: View {
    let tab: BrowserTab
    let isLast: Bool
    let isDuplicate: Bool
    let tint: Color
    @ObservedObject var model: PopupModel
    let popup: TaskbarPopup

    private var hovering: Bool { model.hoveredTab == tab.id }

    var body: some View {
        HStack(spacing: 8) {
            TreeBranch(isLast: isLast)
                .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                .frame(width: 14)
            Circle()
                .fill(tab.isSelected ? tint : Color.clear)
                .overlay(Circle().strokeBorder(Color.primary.opacity(tab.isSelected ? 0 : 0.25), lineWidth: 1))
                .frame(width: 6, height: 6)
            Text(verbatim: tab.title)
                .font(.system(size: 12, weight: tab.isSelected ? .semibold : .regular))
                .foregroundStyle(tab.isSelected ? Color.primary : Color.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            if isDuplicate {
                Text("Duplicate")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 0.75))
            }
            if let site = tab.site {
                SiteChip(site: site)
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .frame(height: PopupLayout.tabRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(hovering ? 0.12 : 0))
                .padding(.leading, 48)
        )
        .contentShape(Rectangle())
        .onHover { model.setHoveredTab(tab.id, window: tab.windowID, $0) }
        .onTapGesture { popup.pickTab(tab) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(tab.isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// The site a tab is on, in its own colour.
struct SiteChip: View {
    let site: String

    var body: some View {
        let hue = SiteColor.hue(for: site)
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hue: hue, saturation: 0.7, brightness: 0.85))
                .frame(width: 5, height: 5)
            Text(verbatim: site)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Color(hue: hue, saturation: 0.55, brightness: 0.9).opacity(0.18), in: Capsule())
        .fixedSize()
    }
}

/// The branch line in front of a tab: down from the window, then right to the tab.
struct TreeBranch: Shape {
    let isLast: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let x = rect.minX + 3.5
        path.move(to: CGPoint(x: x, y: rect.minY))
        path.addLine(to: CGPoint(x: x, y: isLast ? rect.midY - 4 : rect.maxY))
        if isLast {
            path.addQuadCurve(to: CGPoint(x: x + 4, y: rect.midY), control: CGPoint(x: x, y: rect.midY))
        } else {
            path.move(to: CGPoint(x: x, y: rect.midY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// One picture under a browser's tab list: the window under the mouse, else the
/// active window, else the most recent one.
struct PeekPane: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        let row = model.peekWindow.flatMap { id in model.rows.first { $0.id == id } }
            ?? model.rows.first { $0.isActive }
            ?? model.rows.first
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
            if let row {
                if let image = model.thumbnails[row.id] {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .padding(8)
                        .id(row.id)
                        .transition(.opacity)
                } else {
                    Minimap(rect: row.minimap, isMinimized: row.isMinimized, tint: row.tint, icon: row.icon)
                        .padding(14)
                }
            }
        }
        .animation(.easeOut(duration: 0.15), value: row?.id)
        .frame(height: PopupLayout.peekHeight)
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }
}
