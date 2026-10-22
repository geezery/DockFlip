/// Selection state of the ⌥Tab switcher. Pure value type, unit-tested.
public struct SwitcherSelection: Equatable {
    public private(set) var index: Int
    public let count: Int

    /// ⌥Tab starts on the previous window (index 1); ⌥⇧Tab on the last one.
    public init(count: Int, reverse: Bool) {
        self.count = count
        if count <= 1 {
            index = 0
        } else {
            index = reverse ? count - 1 : 1
        }
    }

    public mutating func step(_ delta: Int) {
        guard count > 0 else { return }
        index = ((index + delta) % count + count) % count
    }

    public mutating func select(_ newIndex: Int) {
        guard (0..<count).contains(newIndex) else { return }
        index = newIndex
    }
}
