import Foundation

/// Which windows' pictures the ⌘Tab switcher asks for. Pure, unit-tested.
public enum SwitcherPreviews {
    /// At most this many captures start together.
    public static let batch = 16

    /// The windows to capture now, front first, none of them in `asked`: every
    /// card `SwitcherStack` draws and, with `lookAhead` (as the switcher opens
    /// or the filter changes), the ones behind them, up to `batch` in all.
    /// Asked again after every step, so a window deep in the stack is captured
    /// while it comes into sight, well before it reaches the front.
    public static func toCapture<ID: Hashable>(
        ids: [ID], selection: Int, visibleDepth: Int, asked: Set<ID>, lookAhead: Bool
    ) -> [ID] {
        let count = ids.count
        guard count > 0 else { return [] }
        let front = ((selection % count) + count) % count
        let depth = { (index: Int) -> Int in (index - front + count) % count }
        let drawn = SwitcherStack.drawnIndices(count: count, selection: front, visibleDepth: visibleDepth)
            .sorted { depth($0) < depth($1) }
        var order = drawn
        if lookAhead {
            let inView = Set(drawn)
            order += (0..<count).map { (front + $0) % count }.filter { !inView.contains($0) }
        }
        var picked: [ID] = []
        var seen = asked
        for index in order where picked.count < batch {
            if seen.insert(ids[index]).inserted { picked.append(ids[index]) }
        }
        return picked
    }
}
