import AppKit
import SwiftUI

/// The borderless panels DockFlip draws in: the ⌘Tab switcher, the Dock window
/// list and the snap preview. None of them ever activates DockFlip, so the app
/// you are working in stays the active one.
@MainActor
enum Panels {
    /// Above the Dock, so the window list can sit on top of it.
    static let aboveDock = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

    /// - keyable: may take the keyboard (the switcher), still without activating DockFlip.
    /// - clickThrough: the mouse goes to whatever is underneath (the snap preview).
    static func make(
        level: NSWindow.Level,
        behavior: NSWindow.CollectionBehavior,
        keyable: Bool = false,
        shadow: Bool = false,
        clickThrough: Bool = false
    ) -> NSPanel {
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel: NSPanel = keyable
            ? KeyablePanel(contentRect: .zero, styleMask: style, backing: .buffered, defer: true)
            : NSPanel(contentRect: .zero, styleMask: style, backing: .buffered, defer: true)
        panel.level = level
        panel.collectionBehavior = behavior
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = shadow
        panel.ignoresMouseEvents = clickThrough
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = !keyable
        return panel
    }
}

/// A borderless panel that may become key — take the keyboard — without
/// activating its app (what lets the switcher read keys while Terminal stays active).
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A hosting view that takes the first click, even though DockFlip is never the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// An NSMenuItem that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private var handler: (() -> Void)?

    convenience init(_ title: String, handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(run), keyEquivalent: "")
        self.handler = handler
        self.target = self
    }

    @objc private func run() {
        handler?()
    }
}
