import AppKit
import ApplicationServices

/// The Dock click tap: a quick click on an icon of an app with windows is the
/// Windows taskbar click (`DockClick`); drags and press-and-hold go on to the
/// Dock (`DockPress`). Also ⌃⌥1…9, the same click from the keyboard.
extension DockController {
    /// A press on an icon of an app with windows, held back from the Dock until
    /// it is a click (DockFlip's) or a drag or hold (the Dock's).
    struct HeldPress {
        var press: DockPress
        /// A copy of the mouse-down, posted to the Dock if the press turns out to be its.
        let down: CGEvent
        let bundleID: String
    }

    /// Marks the events DockFlip posts on to the Dock, so its own tap lets them through.
    private static let repostMarker: Int64 = 0x446F_636B_466C_6970 // "DockFlip"

    // MARK: - Clicks on Dock icons

    func installClickTap() {
        let mask = (CGEventMask(1) << CGEventMask(CGEventType.leftMouseDown.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.leftMouseDragged.rawValue))
            | (CGEventMask(1) << CGEventMask(CGEventType.leftMouseUp.rawValue))
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: dockClickCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.app.error("Could not create the Dock click tap")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        clickTap = tap
    }

    /// Returns true when the event is taken over (and must not reach the Dock).
    /// Clicks with ⌘, ⌥, ⌃ or ⇧ always go to the Dock (Show in Finder, Hide Others …).
    ///
    /// A press on an icon of an app with windows is held back (`DockPress`): a quick
    /// click in place is DockFlip's, while a drag or a press-and-hold is posted on
    /// to the Dock, so reordering, removing and the icon's menu keep working.
    ///
    /// Every left click on the Mac waits for this answer, so it comes from memory
    /// (`DockClick`); the click's work runs after the tap has answered.
    fileprivate func click(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let clickTap { CGEvent.tapEnable(tap: clickTap, enable: true) }
            return false
        case _ where event.getIntegerValueField(.eventSourceUserData) == Self.repostMarker:
            // DockFlip's own repost of a held press: it is the Dock's now.
            return false
        case .leftMouseDown:
            // A mouse-up lost while the tap was disabled leaves a press behind; a new press ends it.
            held = nil
            // Cheap checks first: clicks outside the Dock pass straight through.
            let location = event.location
            guard let listFrame = dockListAXFrame, listFrame.contains(location),
                  event.flags.isDisjoint(with: [.maskCommand, .maskAlternate, .maskControl, .maskShift]) else { return false }
            return Perf.shared.measure("dock.click") { pressOnDock(event, at: location) }
        case .leftMouseDragged, .leftMouseUp:
            guard var current = held else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            let action = type == .leftMouseUp
                ? current.press.released(at: event.location, at: now)
                : current.press.moved(to: event.location, at: now)
            held = type == .leftMouseUp ? nil : current
            switch action {
            case .wait:
                // Small wobble before the press is decided: the Dock has not seen a press yet.
                return true
            case .click:
                // Answer the tap first: the click's work may wait on its app.
                let up = event.copy()
                Task { @MainActor [weak self, current] in self?.clicked(current, up: up) }
                return true
            case .handToDock:
                // The Dock gets the held mouse-down first, then this event, in order.
                guard let copy = event.copy() else { return false }
                repost(current.down)
                repost(copy)
                return true
            case .pass:
                return false
            }
        default:
            return false
        }
    }

    /// A mouse-down on the Dock's icon list: held back when it is on an icon of
    /// an app DockFlip knows windows of. No window-server read and no call to
    /// that app here — a hung app would hold up every click on the Mac.
    private func pressOnDock(_ event: CGEvent, at location: CGPoint) -> Bool {
        guard let bundleID = iconBundleID(at: location), registry.hasWindows(bundleID: bundleID),
              let down = event.copy() else { return false }
        popup.hideNow()
        hold(down, bundleID: bundleID)
        return true
    }

    /// The app behind the Dock icon at `location` (AX coordinates), or nil for
    /// folders, the Trash and separators. The highlighted icon answers from
    /// memory; only a press elsewhere asks the Dock (never a hung app: the Dock).
    private func iconBundleID(at location: CGPoint) -> String? {
        let highlighted = hovered.map { (bundleID: $0.bundleID, frame: $0.axFrame) }
        if let bundleID = DockClick.hoveredBundleID(highlighted, at: location) { return bundleID }
        guard let dockApp else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dockApp, Float(location.x), Float(location.y), &hit) == .success,
              let element = hit else { return nil }
        // ⌃⌥1…9's reader: one call to the Dock, and each app's Info.plist read only once.
        return dockItemBundleID(element)
    }

    /// Holds `down` back from the Dock. A one-shot timer hands it over if the
    /// button is still down after `DockPress.holdLimit`, so the Dock's
    /// press-and-hold menu still opens while the mouse stays put.
    private func hold(_ down: CGEvent, bundleID: String) {
        let press = DockPress(start: down.location, startTime: ProcessInfo.processInfo.systemUptime)
        held = HeldPress(press: press, down: down, bundleID: bundleID)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(DockPress.holdLimit))
            self?.holdTimerFired(startTime: press.startTime)
        }
    }

    private func holdTimerFired(startTime: TimeInterval) {
        // Only the press this timer was started for; it may have ended or been replaced.
        guard var current = held, current.press.startTime == startTime else { return }
        // The mouse-up can slip past while the tap is disabled (timeout); a mouse-down
        // posted after it would leave the Dock thinking the button is still held.
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            held = nil
            return
        }
        let action = current.press.timerFired()
        held = current
        if action == .handToDock { repost(current.down) }
    }

    /// Posts an event on to the Dock, marked so this tap lets it through.
    private func repost(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: Self.repostMarker)
        event.post(tap: .cgSessionEventTap)
    }

    /// A click on an app's icon, run just after the tap has answered: the window
    /// list is read here, and the registry's actions wait on the app off the main thread.
    private func clicked(_ press: HeldPress, up: CGEvent?) {
        let windows = registry.switcherWindows().filter { $0.bundleID == press.bundleID }
        let next = action(for: windows, bundleID: press.bundleID)
        if next == .handToDock, let up {
            // Its windows were gone after all (closed on another Space without
            // a word): the Dock gets the click it would have had.
            repost(press.down)
            repost(up)
        } else {
            perform(next, bundleID: press.bundleID)
        }
    }

    /// The Windows taskbar click on the app's windows (`DockClick.action`).
    private func action(for windows: [WindowSnapshot], bundleID: String) -> DockClick.Action {
        DockClick.action(
            windows: windows.map { DockClick.Window(id: $0.id, isMinimized: $0.isMinimized) },
            bundleID: bundleID,
            active: registry.activeWindowID(),
            minimizedByClick: minimizedByClick
        )
    }

    private func perform(_ action: DockClick.Action, bundleID: String) {
        switch action {
        case .restore(let id), .focus(let id):
            minimizedByClick = nil
            registry.focus(id)
        case .minimize(let id):
            registry.minimize(id)
            minimizedByClick = (bundleID, id)
        case .handToDock:
            break
        }
    }

    /// ⌃⌥1…9: the n-th app in the Dock, as Win+1…9 on Windows.
    /// Asks the Dock on every press, so a dragged icon counts at once, but only
    /// for its icon list and the icons up to the n-th app (`DockAppOrder`).
    func activateItem(at index: Int) {
        guard let list = dockList,
              let bundleID = DockAppOrder.app(at: index, in: list.elements(kAXChildrenAttribute), bundleID: { self.dockItemBundleID($0) })
        else { return }
        if let item = windowListItem(for: bundleID) {
            perform(action(for: item.windows, bundleID: bundleID), bundleID: bundleID)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// The bundle ID behind a Dock icon, or nil for folders, the Trash and
    /// separators: subrole and URL in one call to the Dock, no frame, and the
    /// app's Info.plist read once (`bundleIDs`).
    private func dockItemBundleID(_ element: AXUIElement) -> String? {
        // A failed batch read must not shift the count: ask one attribute at a time.
        guard let values = element.copyAttributes([kAXSubroleAttribute, kAXURLAttribute]) else {
            return Self.appBundleID(element)
        }
        guard values[0] as? String == "AXApplicationDockItem",
              let url = values[1] as? URL else { return nil }
        return bundleIDs.bundleID(for: url) { Bundle(url: $0)?.bundleIdentifier }
    }
}

/// Mouse tap callback. Runs on the main run loop.
private func dockClickCallback(_ proxy: CGEventTapProxy, _ type: CGEventType, _ event: CGEvent, _ refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<DockController>.fromOpaque(refcon).takeUnretainedValue()
    let swallow: Bool = MainActor.assumeIsolated { controller.click(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
