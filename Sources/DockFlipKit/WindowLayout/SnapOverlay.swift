import AppKit

/// The translucent "the window will go here" preview shown while dragging a
/// window to a screen edge or corner.
@MainActor
final class SnapOverlay {
    private var panel: NSPanel?

    func show(_ rect: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let inset = rect.insetBy(dx: 6, dy: 6)
        if panel.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().setFrame(inset, display: true)
            }
        } else {
            panel.setFrame(inset, display: true)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = Panels.make(
            level: .floating,
            behavior: [.canJoinAllSpaces, .transient, .ignoresCycle],
            clickThrough: true
        )
        let view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 14
        view.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        view.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        view.layer?.borderWidth = 2
        panel.contentView = view
        return panel
    }
}
