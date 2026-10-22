/// Most-recently-used ordering. Index 0 is the most recent.
public struct MRUList<ID: Hashable> {
    public private(set) var items: [ID]

    public init(_ items: [ID] = []) {
        var seen = Set<ID>()
        self.items = items.filter { seen.insert($0).inserted }
    }

    public mutating func moveToFront(_ id: ID) {
        items.removeAll { $0 == id }
        items.insert(id, at: 0)
    }

    public mutating func appendIfMissing(_ id: ID) {
        if !items.contains(id) { items.append(id) }
    }

    public mutating func remove(_ id: ID) {
        items.removeAll { $0 == id }
    }
}

extension MRUList: Equatable where ID: Equatable {}
