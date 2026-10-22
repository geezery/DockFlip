import AppKit
import SwiftUI

/// Drives the ⌥Tab switcher: takes a snapshot of windows when ⌥Tab is first
/// pressed, moves the selection, and focuses the chosen window on release.
@MainActor
final class SwitcherController {
    private let registry: WindowRegistry
    private let model = SwitcherModel()
    private var panel: NSPanel?
    private var selection: SwitcherSelection?
    private var windowIDs: [CGWindowID] = []

    var isActive: Bool { selection != nil }

    init(registry: WindowRegistry) {
        self.registry = registry
        model.onPick = { [weak self] index in
            self?.commit(at: index)
        }
    }

    /// Returns true when the input was consumed.
    func handle(_ input: SwitcherInput) -> Bool {
        switch input {
        case .optionTab(let shift):
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
            hide()
            return true
        case .optionReleased:
            if let selection { commit(at: selection.index) }
            return false
        }
    }

    // MARK: - Lifecycle

    private func begin(reverse: Bool) -> Bool {
        let windows = registry.switcherWindows()
        guard !windows.isEmpty else { return false }

        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let axScreens = screens.map { Geometry.axRect(fromCocoa: $0.frame, primaryHeight: primaryHeight) }

        windowIDs = windows.map(\.id)
        model.items = windows.map { window in
            let screenIndex = Geometry.bestScreenIndex(for: window.frame, screens: axScreens)
            return SwitcherItem(
                id: window.id,
                title: window.title.isEmpty ? window.appName : window.title,
                appName: window.appName,
                icon: window.icon,
                minimap: screenIndex.map { Geometry.normalized(window.frame, in: axScreens[$0]) },
                isMinimized: window.isMinimized
            )
        }

        let selection = SwitcherSelection(count: windows.count, reverse: reverse)
        self.selection = selection
        model.selection = selection.index
        show()
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

    private func hide() {
        panel?.orderOut(nil)
        selection = nil
        windowIDs = []
    }

    // MARK: - Panel

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let size = SwitcherLayout.panelSize(itemCount: model.items.count)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.midY - size.height / 2 + visible.height * 0.08).rounded()
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: SwitcherLayout.cornerRadius)

        let hosting = NSHostingView(rootView: SwitcherView(model: model))
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
        ])

        panel.contentView = effect
        return panel
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
