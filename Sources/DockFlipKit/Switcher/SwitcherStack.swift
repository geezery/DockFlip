import Foundation

/// Which windows the ⌘Tab stack draws. Pure, unit-tested.
public enum SwitcherStack {
    /// Indices of the cards to draw, in index order: those at depth 0 through
    /// `visibleDepth + 1`, and the one at the very back. Every card deeper than
    /// `visibleDepth` is fully faded out, so leaving the rest out of the view
    /// changes nothing on screen; with 60 windows it keeps ten 3D cards instead
    /// of 60. The two invisible extras keep a ⌘Tab step looking the same: the
    /// card that comes into sight at `visibleDepth` slides in from the depth
    /// behind it, and the front card thrown to the back (or, with ⇧, the back
    /// card brought to the front) is already in the view to animate from.
    public static func drawnIndices(count: Int, selection: Int, visibleDepth: Int) -> [Int] {
        guard count > 0 else { return [] }
        let deepest = min(count - 1, max(0, visibleDepth + 1))
        var depths = Set(0...deepest)
        depths.insert(count - 1)
        let front = ((selection % count) + count) % count
        return depths.map { (front + $0) % count }.sorted()
    }
}
