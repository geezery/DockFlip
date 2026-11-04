import AppKit

/// Aiming at the open list: the list is wider than its icon, so a diagonal
/// towards its far end crosses the neighbouring icon. While the mouse heads for
/// the list (`DockAim`), the neighbour waits instead of switching the list.
extension DockController {
    /// The Dock highlighted `icon` while another icon's list is open. If the mouse
    /// is heading for that list (a diagonal over the neighbour), the list stays and
    /// `icon` waits in `pending`. Returns whether it waits.
    func deferIfAiming(at icon: HoveredIcon) -> Bool {
        guard let shown = listIcon, shown.bundleID != icon.bundleID,
              popup.shownKey == shown.bundleID, let listFrame = popup.visibleFrame else { return false }
        let mouse = NSEvent.mouseLocation
        guard let origin = aim.origin(before: mouse),
              DockAim.isHeading(from: origin, to: mouse, list: listFrame, edge: dockEdge) else { return false }
        pending = icon
        pendingApex = origin
        pendingDistance = DockAim.distance(from: mouse, to: listFrame, edge: dockEdge)
        // The list's icon stays hovered: its list keeps its anchor, and the Dock may
        // have reported the gap between the icons first (which started a hide).
        hovered = shown
        popup.cancelHide()
        restartAimGrace()
        return true
    }

    /// Each mouse move while `pending` waits: reaching the list keeps it, moving
    /// closer inside the triangle waits longer, anything else hands over.
    func followAim(_ mouse: NSPoint, onPopup: Bool) {
        if onPopup {
            endAim()
            popup.cancelHide()
            return
        }
        guard let listFrame = popup.visibleFrame, let apex = pendingApex,
              DockAim.isHeading(from: apex, to: mouse, list: listFrame, edge: dockEdge) else {
            takePending()
            return
        }
        let distance = DockAim.distance(from: mouse, to: listFrame, edge: dockEdge)
        if distance < pendingDistance {
            pendingDistance = distance
            restartAimGrace()
        }
    }

    /// One-shot wait: if the mouse makes no progress towards the list in time, it
    /// is resting on the neighbour, which then takes over.
    func restartAimGrace() {
        pendingTask?.cancel()
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.aimGrace)
            guard !Task.isCancelled else { return }
            self?.takePending()
        }
    }

    /// The mouse was going to the neighbour after all: its list takes over.
    func takePending() {
        guard let icon = pending else { return }
        endAim()
        enter(icon)
    }

    func endAim() {
        pendingTask?.cancel()
        pendingTask = nil
        pending = nil
        pendingApex = nil
    }

    /// A press while aiming belongs to the icon under the mouse (`iconBundleID`
    /// asks the Dock), and no list may switch in after it.
    func dockPressedWhileAiming() {
        guard let icon = pending else { return }
        endAim()
        hovered = icon
        listIcon = icon
    }
}
