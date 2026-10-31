import CoreGraphics

/// The free frames snapped windows go back to on ⌃⌥↓ or a drag off the snap.
/// Each write drops the windows no longer tracked: a window closed while snapped
/// would otherwise keep its entry for the life of the process, and a reused
/// window id could take another window's old frame.
struct SnapRestoreFrames {
    private(set) var frames: [CGWindowID: CGRect] = [:]

    subscript(id: CGWindowID) -> CGRect? { frames[id] }

    /// Remembers `frame` for `id`, keeping only the windows in `live` besides it.
    mutating func remember<Live: Sequence>(_ frame: CGRect, for id: CGWindowID, live: Live) where Live.Element == CGWindowID {
        let alive = Set(live)
        frames = frames.filter { alive.contains($0.key) }
        frames[id] = frame
    }

    /// The frame for `id`, forgotten as it is handed back.
    @discardableResult
    mutating func take(_ id: CGWindowID) -> CGRect? {
        frames.removeValue(forKey: id)
    }
}
