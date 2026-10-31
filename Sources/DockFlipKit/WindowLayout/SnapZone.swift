import CoreGraphics

/// The drag-snap zone under the mouse, Windows 11 style: side edges give halves,
/// the top edge maximizes, near a corner gives quarters. Edges shared with
/// another display do not count. Cocoa coordinates (y grows upwards).
enum SnapZone {
    static let edge: CGFloat = 3
    static let corner: CGFloat = 80

    /// The region under `point` and the index in `screens` (display frames) of
    /// the display it is on, or nil away from the edges.
    static func zone(at point: CGPoint, screens: [CGRect]) -> (region: SnapRegion, screen: Int)? {
        guard let index = screens.firstIndex(where: { contains($0, point) }) else { return nil }
        let frame = screens[index]

        func onScreen(_ p: CGPoint) -> Bool { screens.contains { contains($0, p) } }

        let atLeft = point.x <= frame.minX + edge && !onScreen(CGPoint(x: frame.minX - 2, y: point.y))
        let atRight = point.x >= frame.maxX - edge - 1 && !onScreen(CGPoint(x: frame.maxX + 2, y: point.y))
        let atTop = point.y >= frame.maxY - edge - 1 && !onScreen(CGPoint(x: point.x, y: frame.maxY + 2))
        let nearTop = point.y >= frame.maxY - corner
        let nearBottom = point.y <= frame.minY + corner
        let nearLeft = point.x <= frame.minX + corner
        let nearRight = point.x >= frame.maxX - corner

        if atLeft { return (nearTop ? .topLeft : nearBottom ? .bottomLeft : .leftHalf, index) }
        if atRight { return (nearTop ? .topRight : nearBottom ? .bottomRight : .rightHalf, index) }
        if atTop { return (nearLeft ? .topLeft : nearRight ? .topRight : .maximized, index) }
        return nil
    }

    /// `NSMouseInRect(point, rect, false)` without AppKit: in an unflipped view the
    /// left and top edges are inside, the right and bottom edges are not.
    static func contains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        point.x >= rect.minX && point.x < rect.maxX && point.y > rect.minY && point.y <= rect.maxY
    }
}
