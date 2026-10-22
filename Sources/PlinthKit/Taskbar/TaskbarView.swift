import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One button on the taskbar: an app (buttons combined, the default) or a single
/// window (never combine).
struct TaskbarItem: Identifiable {
    let id: String
    let appKey: String
    let bundleID: String?
    let pid: pid_t?
    let name: String
    let icon: NSImage?
    /// Window title, when buttons are not combined.
    let label: String?
    /// This item's windows on this display, most recent first.
    let windowIDs: [CGWindowID]
    let isRunning: Bool
    let isActive: Bool
    let badge: String?
    let isNotResponding: Bool
}

@MainActor
final class TaskbarModel: ObservableObject {
    let displayID: CGDirectDisplayID
    @Published var items: [TaskbarItem] = []
    @Published var hoveredID: String?
    @Published var barHeight: CGFloat = 48
    /// Hover state of the clock and the show-desktop strip (no @State: it is a
    /// macro that the Command Line Tools cannot expand).
    @Published var clockHovered = false
    @Published var stripHovered = false
    /// Item frames in the taskbar's own coordinates (top-left origin).
    var itemFrames: [String: CGRect] = [:]

    init(displayID: CGDirectDisplayID) {
        self.displayID = displayID
    }
}

private struct ItemFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct TaskbarView: View {
    @ObservedObject var model: TaskbarModel
    let controller: TaskbarController

    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(model.items) { item in
                    TaskbarButton(item: item, isHovered: model.hoveredID == item.id, barHeight: model.barHeight)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ItemFramesKey.self,
                                    value: [item.id: geo.frame(in: .named("taskbar"))]
                                )
                            }
                        )
                        .onTapGesture {
                            controller.click(item.id, on: model.displayID)
                        }
                        .onDrop(
                            of: [UTType.fileURL],
                            isTargeted: Binding(
                                get: { false },
                                set: { targeted in
                                    MainActor.assumeIsolated {
                                        controller.dragHover(item.id, on: model.displayID, targeted: targeted)
                                    }
                                }
                            )
                        ) { _ in false }
                }
            }

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ClockButton(isHovered: model.clockHovered, onHover: { model.clockHovered = $0 }) {
                    controller.toggleCalendar(on: model.displayID)
                }
                ShowDesktopStrip(isHovered: model.stripHovered, onHover: { model.stripHovered = $0 }) {
                    controller.showDesktop()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: TaskbarStyle.background))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
        }
        .coordinateSpace(name: "taskbar")
        .onPreferenceChange(ItemFramesKey.self) { frames in
            MainActor.assumeIsolated { model.itemFrames = frames }
        }
    }
}

struct TaskbarButton: View {
    let item: TaskbarItem
    let isHovered: Bool
    let barHeight: CGFloat

    private var iconSize: CGFloat { TaskbarStyle.iconSize(forBarHeight: barHeight) }
    private var buttonHeight: CGFloat { max(36, barHeight - 6) }

    private var indicatorWidth: CGFloat {
        if item.isActive { return item.label == nil ? 16 : 28 }
        return item.windowIDs.isEmpty ? 0 : 6
    }

    var body: some View {
        HStack(spacing: 8) {
            AppIconView(icon: item.icon, size: iconSize)
                .saturation(item.isNotResponding ? 0 : 1)
                .opacity(item.isNotResponding ? 0.55 : 1)
            if let label = item.label {
                Text(verbatim: item.isNotResponding ? "\(label) (\(L("Not responding")))" : label)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 118, alignment: .leading)
            }
        }
        .padding(.horizontal, item.label == nil ? 8 : 10)
        .frame(minWidth: iconSize + 16, minHeight: buttonHeight, maxHeight: buttonHeight)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(item.isActive ? 0.10 : (isHovered ? 0.06 : 0)))
        )
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(item.isActive ? Color.accentColor : Color.secondary)
                .frame(width: indicatorWidth, height: 3)
                .padding(.bottom, 2)
        }
        .overlay(alignment: .topLeading) {
            if let badge = item.badge {
                Text(verbatim: badge)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(Color.red))
                    .offset(x: iconSize, y: 2)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.15), value: item.isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: (item.label ?? item.name) + (item.isNotResponding ? ", " + L("Not responding") : "")))
        .accessibilityAddTraits(.isButton)
    }
}

struct ClockButton: View {
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .trailing, spacing: 1) {
                Text(context.date, format: .dateTime.hour().minute())
                Text(context.date, format: .dateTime.day().month(.defaultDigits).year())
            }
            .font(.system(size: 12))
        }
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
                .padding(.vertical, 4)
        )
        .contentShape(Rectangle())
        .onHover(perform: onHover)
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The thin strip at the far right that shows the desktop, as on Windows.
struct ShowDesktopStrip: View {
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let action: () -> Void

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(isHovered ? 0.08 : 0.001))
            .frame(width: 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 1).padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .onHover(perform: onHover)
            .onTapGesture(perform: action)
            .accessibilityLabel(Text("Show desktop"))
            .accessibilityAddTraits(.isButton)
    }
}

/// Hosts the taskbar and adds hover tracking, right-click and middle-click.
/// Hover uses an AppKit tracking area that is active even though Plinth is
/// never the active app.
final class TaskbarHostingView: NSHostingView<TaskbarView> {
    weak var controller: TaskbarController?
    var displayID: CGDirectDisplayID = 0
    var itemFrames: () -> [String: CGRect] = { [:] }
    private var hoverArea: NSTrackingArea?
    private var hoveredID: String?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        setHovered(itemID(at: event))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovered(nil)
    }

    private func setHovered(_ id: String?) {
        guard id != hoveredID else { return }
        if let old = hoveredID { controller?.hover(old, on: displayID, inside: false) }
        hoveredID = id
        if let id { controller?.hover(id, on: displayID, inside: true) }
    }

    private func itemID(at event: NSEvent) -> String? {
        let local = convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        return itemFrames().first { $0.value.contains(point) }?.key
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let id = itemID(at: event), let menu = controller?.contextMenu(for: id, on: displayID) else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2, let id = itemID(at: event) {
            controller?.middleClick(id, on: displayID)
        } else {
            super.otherMouseUp(with: event)
        }
    }
}
