import AppKit
import SwiftUI

/// Puts the ⌘Tab switcher on screen and takes it off again. `SwitcherController`
/// decides when; this does the AppKit part, so tests can pass a fake that draws nothing.
@MainActor
protocol SwitcherPresenter: AnyObject {
    /// Keys pressed while the switcher is shown, handed to the controller.
    var onInput: ((SwitcherInput) -> Void)? { get set }
    /// Orders the switcher in and takes the keyboard, but invisible and
    /// click-through until `draw()`: keys pressed during the hold (⌘Q, arrows)
    /// reach the switcher, not the app you are leaving.
    func show()
    /// Makes what `show()` ordered in visible and clickable.
    func draw()
    /// Takes the switcher off screen. `returningToPreviousApp` (on cancel) gives
    /// the app you came from its activation back, should DockFlip have taken it.
    func hide(returningToPreviousApp: Bool)
}

/// The switcher's full-screen panel. It is a non-activating panel that is made
/// key *without activating DockFlip* — what AltTab and DockDoor do. Since macOS
/// 14, an app in the background cannot reliably activate itself (cooperative
/// activation), but a non-activating panel can always become key. The app you
/// came from stays the active app, so cancelling needs no re-activation, and keys
/// reach the panel even while that app holds secure keyboard input (where event
/// taps see no key presses at all).
@MainActor
final class SwitcherPanel: SwitcherPresenter {
    private let model: SwitcherModel
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    /// Between `show()` and `hide()`: the panel wants the keyboard.
    private var isShown = false
    private var localMonitor: Any?
    private var resignKeyToken: NSObjectProtocol?

    var onInput: ((SwitcherInput) -> Void)?

    init(model: SwitcherModel) {
        self.model = model
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        guard let screen = DisplayLayout.screen(containingMouse: NSEvent.mouseLocation) else { return }
        panel.setFrame(screen.frame, display: true)

        // Take the keyboard while switching, without activating DockFlip (see the type comment).
        let own = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != own {
            previousApp = front
        }
        isShown = true
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installLocalMonitor()
        let isKey = panel.isKeyWindow
        Log.keys.debug("Switcher panel shown, key window: \(isKey, privacy: .public)")
    }

    func draw() {
        guard isShown, let panel else { return }
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
    }

    func hide(returningToPreviousApp: Bool) {
        let previous = previousApp
        let wasActivated = NSApp.isActive
        isShown = false
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        panel?.orderOut(nil)
        previousApp = nil
        // Normally DockFlip never became active and the previous app still is.
        if returningToPreviousApp, wasActivated {
            _ = previous?.activate(from: NSRunningApplication.current, options: [])
        }
    }

    /// Another window can take key status while the switcher is open (an app
    /// opening a window, a notification). Take it back on the next turn of the
    /// run loop — making it key again inside the notification is ignored.
    private func observeResignKey(of panel: NSPanel) {
        resignKeyToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isShown, let panel = self.panel else { return }
                Log.keys.debug("Switcher panel lost key status; taking it back")
                panel.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// The panel is key, so every key but Esc (see `SwitcherKeyTaps`) arrives here
    /// as an ordinary app event, even while another app holds secure keyboard input.
    private func installLocalMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let swallow: Bool = MainActor.assumeIsolated { self?.handleLocal(event) ?? false }
            return swallow ? nil : event
        }
    }

    /// Returns true when the event must not reach anything else.
    private func handleLocal(_ event: NSEvent) -> Bool {
        guard isShown else { return false }
        if event.type == .flagsChanged {
            if !event.modifierFlags.contains(.command) { onInput?(.commandReleased) }
            return false
        }
        let input = SwitcherInput.from(
            keyCode: UInt32(event.keyCode),
            command: event.modifierFlags.contains(.command),
            shift: event.modifierFlags.contains(.shift),
            text: SwitcherText.typed(event)
        )
        if let input { onInput?(input) }
        return true // nothing else reaches any app while switching
    }

    private func makePanel() -> NSPanel {
        // Above menus, on every Space and over full-screen apps; takes the keyboard.
        let panel = Panels.make(
            level: .popUpMenu,
            behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle],
            keyable: true
        )

        let hosting = FirstMouseHostingView(rootView: SwitcherView(model: model))
        hosting.sizingOptions = []
        panel.contentView = hosting
        observeResignKey(of: panel)
        return panel
    }
}
