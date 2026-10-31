import CoreGraphics

/// Which remembered windows to put back after a display change. Pure, so it is tested;
/// the frames come from the registry's memory, never from Accessibility, because the
/// restore runs on the main thread where a hung app would cost 1 s per window.
enum PlacementRestore {
    /// What the registry knows of a window now.
    enum Known: Equatable {
        /// Not in the registry, or minimized: leave it alone.
        case skip
        /// Tracked, but its frame was never read: move it, setFrame is cheap and async.
        case unknownFrame
        case frame(CGRect)
    }

    /// The windows to move and where, sorted by ID so the order is stable.
    static func moves(
        layout: [CGWindowID: CGRect], screens: [CGRect], known: [CGWindowID: Known]
    ) -> [(id: CGWindowID, frame: CGRect)] {
        layout.keys.sorted().compactMap { id -> (id: CGWindowID, frame: CGRect)? in
            guard let frame = layout[id], screens.contains(where: { $0.intersects(frame) }) else { return nil }
            switch known[id] ?? .skip {
            case .skip: return nil
            case .unknownFrame: return (id, frame)
            case .frame(let current): return current.integral == frame.integral ? nil : (id, frame)
            }
        }
    }
}
