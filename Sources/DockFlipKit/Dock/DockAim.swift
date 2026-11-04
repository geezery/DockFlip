import CoreGraphics

/// Tells whether the mouse is on its way to the open window list, so that
/// crossing a neighbouring Dock icon on a diagonal does not switch the list.
///
/// The list is wider than its icon, so the straight way to its far end passes
/// over the next icon. macOS submenus solve the same problem with a triangle:
/// its tip is where the mouse was, its base is the list's near edge. A mouse
/// moving inside it is aiming at the list; anything else is a real move to
/// the other icon.
struct DockAim {
    /// The mouse's last few distinct positions (Cocoa coordinates), oldest first.
    /// A few, not two: one mouse event moves a pixel or two, too little to say
    /// which way the hand is going.
    private(set) var trail: [CGPoint] = []
    static let trailLength = 4

    /// Room around the list's near edge, so aiming at its very corner still counts.
    /// Generous on purpose: a wrong guess costs only `DockController.aimGrace`.
    static let slack: CGFloat = 20

    /// Records a mouse position; repeats of the same position are ignored, so the
    /// trail always holds a direction.
    mutating func moved(to point: CGPoint) {
        guard point != trail.last else { return }
        trail.append(point)
        if trail.count > Self.trailLength { trail.removeFirst() }
    }

    /// Where the mouse came from on its way to `current`: the oldest remembered
    /// position. The Dock can report the new icon before or after the mouse event
    /// for the same move arrives, so `current` may already be in the trail.
    func origin(before current: CGPoint) -> CGPoint? {
        trail.first { $0 != current }
    }

    /// Whether moving from `origin` to `point` heads for `list`: `point` lies in the
    /// triangle between `origin` and the list's edge facing the Dock.
    static func isHeading(from origin: CGPoint, to point: CGPoint, list: CGRect, edge: DockEdge) -> Bool {
        guard point != origin else { return false }
        let a: CGPoint, b: CGPoint
        switch edge {
        case .bottom:
            a = CGPoint(x: list.minX - slack, y: list.minY)
            b = CGPoint(x: list.maxX + slack, y: list.minY)
        case .left:
            a = CGPoint(x: list.minX, y: list.minY - slack)
            b = CGPoint(x: list.minX, y: list.maxY + slack)
        case .right:
            a = CGPoint(x: list.maxX, y: list.minY - slack)
            b = CGPoint(x: list.maxX, y: list.maxY + slack)
        }
        return contains(point, triangle: (origin, a, b))
    }

    /// How far `point` still is from the list's edge facing the Dock.
    static func distance(from point: CGPoint, to list: CGRect, edge: DockEdge) -> CGFloat {
        switch edge {
        case .bottom: list.minY - point.y
        case .left: list.minX - point.x
        case .right: point.x - list.maxX
        }
    }

    /// Point in triangle by the signs of the three edge cross products. A point on
    /// an edge counts as inside, except the tip itself (handled by the caller).
    private static func contains(_ p: CGPoint, triangle t: (CGPoint, CGPoint, CGPoint)) -> Bool {
        func cross(_ o: CGPoint, _ u: CGPoint, _ v: CGPoint) -> CGFloat {
            (u.x - o.x) * (v.y - o.y) - (u.y - o.y) * (v.x - o.x)
        }
        let d1 = cross(t.0, t.1, p)
        let d2 = cross(t.1, t.2, p)
        let d3 = cross(t.2, t.0, p)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }
}
