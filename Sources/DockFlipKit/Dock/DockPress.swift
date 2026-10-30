import CoreGraphics
import Foundation

/// A press on a Dock icon that DockFlip held back from the Dock: is it a click
/// (DockFlip's minimize / restore) or the Dock's own drag or press-and-hold?
/// Pure, unit-tested.
///
/// The mouse-down is held while the press is undecided. A quick release in place
/// is a click. Moving past a few points or holding on hands the press to the Dock:
/// the held mouse-down is posted to it and the rest of the press goes through, so
/// dragging an icon and its press-and-hold menu keep working.
struct DockPress: Equatable {
    /// How far the mouse may wander (points) and still be a click.
    static let moveTolerance: CGFloat = 4
    /// How long a press may last (seconds) and still be a click.
    static let holdLimit: TimeInterval = 0.5

    enum Action: Equatable {
        /// Undecided: keep holding the mouse-down.
        case wait
        /// A click: DockFlip acts, the mouse-up never reaches the Dock.
        case click
        /// A drag or a hold: post the held mouse-down to the Dock, then let the rest through.
        case handToDock
        /// Already the Dock's: let the event through untouched.
        case pass
    }

    let start: CGPoint
    let startTime: TimeInterval
    /// The press was handed to the Dock; everything after it is the Dock's.
    private(set) var handedToDock = false

    init(start: CGPoint, startTime: TimeInterval) {
        self.start = start
        self.startTime = startTime
    }

    /// The mouse moved with the button down.
    mutating func moved(to point: CGPoint, at time: TimeInterval) -> Action {
        guard !handedToDock else { return .pass }
        guard isDrag(to: point) || isHeld(at: time) else { return .wait }
        handedToDock = true
        return .handToDock
    }

    /// The hold timer (`holdLimit` after the press) fired while the button is
    /// still down: the press is a hold. The timer is the authority here, so a
    /// sleep that measures a hair short on another clock still hands it over.
    mutating func timerFired() -> Action {
        guard !handedToDock else { return .pass }
        handedToDock = true
        return .handToDock
    }

    /// The button came up. The timer may not have run yet (a busy main thread),
    /// so the hold is checked here too.
    mutating func released(at point: CGPoint, at time: TimeInterval) -> Action {
        guard !handedToDock else { return .pass }
        if isDrag(to: point) || isHeld(at: time) {
            handedToDock = true
            return .handToDock
        }
        return .click
    }

    private func isDrag(to point: CGPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) > Self.moveTolerance
    }

    private func isHeld(at time: TimeInterval) -> Bool {
        time - startTime >= Self.holdLimit
    }
}
