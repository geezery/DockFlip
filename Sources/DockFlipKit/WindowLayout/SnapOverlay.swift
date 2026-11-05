import AppKit
import SwiftUI

/// The translucent "the window will go here" preview shown while dragging a
/// window to a screen edge or corner.
@MainActor
final class SnapOverlay {
    private var panel: NSPanel?
    private var hintView: NSHostingView<SnapHintView>?
    private var hint: String?

    /// `hint`: a line in the middle of the preview, or nil for none.
    func show(_ rect: NSRect, hint: String? = nil) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // Drag events come many times a second; SwiftUI redraws only on a change.
        if hint != self.hint {
            self.hint = hint
            hintView?.rootView = SnapHintView(text: hint)
        }
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

        let hosting = NSHostingView(rootView: SnapHintView(text: hint))
        hosting.sizingOptions = [] // the preview's frame decides the size, not SwiftUI
        hosting.frame = view.bounds
        hosting.autoresizingMask = [.width, .height]
        view.addSubview(hosting)
        hintView = hosting
        return panel
    }
}

/// The hint in the middle of the preview, on a material like the switcher's
/// title: the preview is see-through, and bare text would sit on whatever
/// window is underneath. It wraps in a narrow quarter. The triangle is the
/// menu item's, so the two read as one thing.
struct SnapHintView: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .accessibilityHidden(true)
                Text(verbatim: text)
            }
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frostedBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(16)
        }
    }
}
