import AppKit
import SwiftUI

struct PopupRow: Identifiable {
    let id: CGWindowID
    let title: String
    let icon: NSImage?
    let minimap: CGRect?
    let isMinimized: Bool
    let isActive: Bool
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

    func setHovered(_ id: CGWindowID, _ inside: Bool) {
        if inside {
            hoveredRow = id
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

    static func size(rows: Int, previews: Bool) -> NSSize {
        if rows == 0 {
            return NSSize(width: 220, height: 44)
        }
        if previews {
            let columns = min(rows, 5)
            return NSSize(width: CGFloat(columns) * cardWidth + 16, height: 36 + cardHeight + 12)
        }
        let visible = CGFloat(min(rows, maxVisibleRows))
        return NSSize(width: listWidth, height: 36 + visible * rowHeight + 10)
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
    private var previewTask: Task<Void, Never>?
    private var current: (itemID: String, displayID: CGDirectDisplayID)?

    var isVisible: Bool { panel?.isVisible == true }

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
        previewTask?.cancel()
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
        guard let source, let item = source.item(itemID, on: displayID),
              let anchor = source.anchorRect(for: itemID, on: displayID) else { return }
        let changedItem = current?.itemID != itemID
        current = (itemID, displayID)

        let screens = NSScreen.screens
        let axScreens = screens.map { DisplayLayout.axFrame(of: $0) }
        let activeID = registry.activeWindowID()
        model.title = item.isNotResponding ? "\(item.name) — \(L("Not responding"))" : item.name
        model.rows = item.windowIDs.compactMap { id -> PopupRow? in
            guard let window = registry.window(id) else { return nil }
            let index = Geometry.bestScreenIndex(for: window.frame, screens: axScreens)
            return PopupRow(
                id: id,
                title: window.title.isEmpty ? window.appName : window.title,
                icon: window.icon,
                minimap: index.map { Geometry.normalized(window.frame, in: axScreens[$0]) },
                isMinimized: window.isMinimized,
                isActive: id == activeID
            )
        }
        let previews = PreviewProvider.shared.isAvailable && !model.rows.isEmpty
        model.showsPreviews = previews
        if changedItem { model.thumbnails = [:] }

        let size = PopupLayout.size(rows: model.rows.count, previews: previews)
        let screenFrame = screens.first { NSMouseInRect(NSPoint(x: anchor.midX, y: anchor.midY), $0.frame, false) }?.frame ?? anchor
        let x = min(max(anchor.midX - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let frame = NSRect(x: x.rounded(), y: (anchor.maxY + 6).rounded(), width: size.width, height: size.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()

        if previews { loadPreviews(for: item.windowIDs) }
    }

    private func loadPreviews(for ids: [CGWindowID]) {
        previewTask?.cancel()
        previewTask = Task { @MainActor [weak self] in
            for id in ids.prefix(5) {
                guard !Task.isCancelled, let self, let window = self.registry.window(id) else { return }
                let image = await PreviewProvider.shared.thumbnail(for: window)
                // The popup may have closed while capturing: drop the image then.
                guard !Task.isCancelled, self.isVisible else { return }
                if let image { self.model.thumbnails[id] = image }
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
                if model.showsPreviews {
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
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            Minimap(rect: row.minimap, isMinimized: row.isMinimized)
                .frame(width: 48, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title)
                    .font(.system(size: 13, weight: row.isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.isMinimized {
                    Text("Minimized").font(.system(size: 11)).foregroundStyle(.secondary)
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
                .fill(Color.accentColor.opacity(hovering ? 0.12 : 0))
        )
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
                    AppIconView(icon: row.icon, size: 40).opacity(row.isMinimized ? 0.5 : 1)
                }
            }
            .frame(width: 188, height: 112)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(6)
        .frame(width: PopupLayout.cardWidth - 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(hovering ? 0.12 : 0))
        )
        .contentShape(Rectangle())
        .onHover { model.setHovered(row.id, $0) }
        .onTapGesture { popup.pick(row.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
