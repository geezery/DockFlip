import AppKit
import SwiftUI

/// The calendar that opens from the taskbar clock.
@MainActor
final class CalendarFlyout {
    private var panel: NSPanel?
    private var monitor: Any?
    private let calendarModel = CalendarModel()

    var isVisible: Bool { panel?.isVisible == true }

    func toggle(anchor: NSRect) {
        if isVisible {
            close()
        } else {
            show(anchor: anchor)
        }
    }

    func close() {
        panel?.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func show(anchor: NSRect) {
        calendarModel.selection = Date()
        let hosting = FirstMouseHostingView(rootView: CalendarView(model: calendarModel))
        let size = hosting.fittingSize
        let panel = self.panel ?? PanelFactory.make(level: PanelFactory.popupLevel, shadow: true, canBecomeKey: true)
        self.panel = panel
        panel.contentView = hosting

        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: anchor.midX, y: anchor.midY), $0.frame, false) }?.frame ?? anchor
        let x = min(anchor.maxX - size.width, screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.maxY + 6, width: size.width, height: size.height), display: true)
        panel.makeKeyAndOrderFront(nil)

        // A click anywhere in another app closes it, as on Windows.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

/// Holds the picked date (no @State: it is a macro that the Command Line Tools cannot expand).
@MainActor
final class CalendarModel: ObservableObject {
    @Published var selection = Date()
}

struct CalendarView: View {
    @ObservedObject var model: CalendarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.system(size: 15, weight: .semibold))
            DatePicker("", selection: $model.selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}
