import CoreGraphics

/// Tells a window drag from a click, a text selection or a resize, for
/// drag-to-edge snapping. A mouse down stores only where it happened: the window
/// under the mouse and its frame are looked up once the mouse has moved past
/// `threshold`, so a plain click reads neither the window list nor Accessibility
/// (which blocks while the clicked app hangs). Mouse points are in Cocoa space,
/// frames in AX space.
struct SnapDrag {
    /// How far the mouse moves before the press counts as a drag.
    static let threshold: CGFloat = 8
    /// Past this distance with the window still in place, it is not a window drag.
    static let giveUp: CGFloat = 60

    enum Phase: Equatable {
        /// Pressed, not yet moved past `threshold`.
        case pressed
        /// Past `threshold` over a tracked window: does the window follow the mouse?
        case watching(windowID: CGWindowID, frame: CGRect, mouse: CGPoint)
        /// The window follows the mouse: snap zones apply.
        case windowDrag(windowID: CGWindowID, startFrame: CGRect)
        /// A selection, a resize, or a drag over no tracked window.
        case ignored
    }

    let startMouse: CGPoint
    private(set) var phase: Phase = .pressed

    init(startMouse: CGPoint) {
        self.startMouse = startMouse
    }

    /// The dragged window and its frame at the mouse down, once it is a window drag.
    var window: (id: CGWindowID, startFrame: CGRect)? {
        guard case .windowDrag(let id, let startFrame) = phase else { return nil }
        return (id, startFrame)
    }

    /// One drag event. `windowUnder` finds the tracked window under the mouse
    /// with its frame (once, at `threshold`); `frame` reads that window's frame
    /// again. Neither is called once the drag is decided.
    mutating func moved(to mouse: CGPoint,
                        windowUnder: (CGPoint) -> (id: CGWindowID, frame: CGRect)?,
                        frame: (CGWindowID) -> CGRect?) {
        switch phase {
        case .pressed:
            guard Self.distance(from: startMouse, to: mouse) > Self.threshold else { return }
            guard let found = windowUnder(mouse) else {
                phase = .ignored
                return
            }
            phase = .watching(windowID: found.id, frame: found.frame, mouse: mouse)

        case .watching(let id, let seen, let seenMouse):
            guard let now = frame(id) else {
                phase = .ignored
                return
            }
            let moved = abs(now.minX - seen.minX) + abs(now.minY - seen.minY) > 4
            let resized = abs(now.width - seen.width) + abs(now.height - seen.height) > 2
            if moved && !resized {
                phase = .windowDrag(windowID: id, startFrame: Self.startFrame(seen, at: seenMouse, pressedAt: startMouse))
            } else if resized || Self.distance(from: startMouse, to: mouse) > Self.giveUp {
                phase = .ignored
            }

        case .windowDrag, .ignored:
            break
        }
    }

    /// Where a window that follows the mouse was at the mouse down: `frame` seen
    /// with the mouse at `mouse`, moved back by the mouse's travel since `pressedAt`.
    /// Cocoa's y grows upwards and AX's downwards.
    static func startFrame(_ frame: CGRect, at mouse: CGPoint, pressedAt start: CGPoint) -> CGRect {
        frame.offsetBy(dx: start.x - mouse.x, dy: mouse.y - start.y)
    }

    static func distance(from a: CGPoint, to b: CGPoint) -> CGFloat {
        ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot()
    }
}
