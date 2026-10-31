import CoreGraphics

/// Which windows of the Dock list get a picture, and when.
///
/// A list opens capturing its first eight windows at once: more side by side
/// slows the list and ScreenCaptureKit for little gain, since the cards layout
/// shows at most five. In the list-with-peek-pane layout (many windows) the
/// pane shows the hovered window's picture, so a window past the first eight is
/// captured on its own when the mouse reaches it.
enum WindowListPreviews {
    static let firstBatchSize = 8

    /// The windows captured when the list opens, most recent first.
    static func firstBatch(_ ids: [CGWindowID]) -> [CGWindowID] {
        Array(ids.prefix(firstBatchSize))
    }

    /// The hovered window to capture now, or nil when it is not in the list, is
    /// already loading (in the first batch or an earlier hover), or has a picture.
    static func onHover(_ hovered: CGWindowID?, listed: [CGWindowID], requested: Set<CGWindowID>,
                        shown: Set<CGWindowID>) -> CGWindowID? {
        guard let hovered, listed.contains(hovered),
              !requested.contains(hovered), !shown.contains(hovered) else { return nil }
        return hovered
    }
}
