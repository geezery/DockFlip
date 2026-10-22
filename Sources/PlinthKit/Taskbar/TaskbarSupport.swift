import AppKit
import SwiftUI

/// Panels used by the taskbar, its hover popup and the calendar.
@MainActor
enum PanelFactory {
    /// Just above the Dock, so the taskbar covers the space the Dock reserves.
    static let taskbarLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
    static let popupLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)

    static func make(level: NSWindow.Level, shadow: Bool, canBecomeKey: Bool = false) -> NSPanel {
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel: NSPanel
        if canBecomeKey {
            panel = KeyablePanel(contentRect: .zero, styleMask: style, backing: .buffered, defer: true)
        } else {
            panel = NSPanel(contentRect: .zero, styleMask: style, backing: .buffered, defer: true)
        }
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = shadow
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        // Visible on every Space, never in full-screen apps, never in ⌘` cycling.
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        return panel
    }
}

/// Taskbar colours (Windows 11: light #F3F3F3, dark #202020). Fully opaque, so the
/// real Dock underneath never shows through and never gets the mouse.
enum TaskbarStyle {
    static let background = NSColor(name: "PlinthTaskbarBackground") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.125, green: 0.125, blue: 0.133, alpha: 1)
            : NSColor(srgbRed: 0.953, green: 0.953, blue: 0.957, alpha: 1)
    }

    /// Icon size for a bar of `height`: as large as the Dock's own icons.
    static func iconSize(forBarHeight height: CGFloat) -> CGFloat {
        min(48, max(24, (height * 0.66).rounded()))
    }
}

/// A borderless panel that may become key (for controls such as the date picker),
/// still without activating Plinth.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Hosting view that reacts to the first click even though Plinth is never the active app.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// NSMenuItem that runs a closure.
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

/// Windows 11 "Show desktop": hides every app, and a second press brings them back.
@MainActor
enum ShowDesktop {
    private static var hiddenApps: [NSRunningApplication] = []

    static func toggle() {
        let stillHidden = hiddenApps.filter { !$0.isTerminated && $0.isHidden }
        if !stillHidden.isEmpty {
            for app in stillHidden { app.unhide() }
            hiddenApps = []
            return
        }
        let own = ProcessInfo.processInfo.processIdentifier
        hiddenApps = NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular && !app.isHidden && app.processIdentifier != own && app.hide()
        }
    }
}

/// Unread counts the apps put on their Dock icons, read from the Dock's
/// Accessibility tree. Keyed by app name, as the Dock shows it.
@MainActor
enum DockBadges {
    static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return [:]
        }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        var result: [String: String] = [:]
        for list in element.elements(kAXChildrenAttribute) where list.string(kAXRoleAttribute) == kAXListRole {
            for item in list.elements(kAXChildrenAttribute) {
                guard let title = item.string(kAXTitleAttribute),
                      let label = item.string("AXStatusLabel"), !label.isEmpty else { continue }
                result[title] = label
            }
        }
        return result
    }
}

/// Sends ⌘N to an app — the generic "new window" every Mac app understands.
@MainActor
enum NewWindow {
    static func open(in app: NSRunningApplication) {
        let pid = app.processIdentifier
        AXUIElementCreateApplication(pid).set(kAXFrontmostAttribute, kCFBooleanTrue)
        _ = app.activate(options: [])
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            let source = CGEventSource(stateID: .hidSystemState)
            let keyN: CGKeyCode = 45
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyN, keyDown: isDown)
                event?.flags = .maskCommand
                event?.postToPid(pid)
            }
        }
    }
}
