import AppKit

@MainActor
extension WindowRegistry {
    /// Initial MRU order follows the current stacking order; minimized windows go last.
    func seedMRUFromZOrder() {
        let zOrder = WindowServer.onScreenIDs().filter { windows[$0] != nil }
        var ordered = MRUList(zOrder)
        for id in mru.items { ordered.appendIfMissing(id) }
        mru = ordered
    }
}
