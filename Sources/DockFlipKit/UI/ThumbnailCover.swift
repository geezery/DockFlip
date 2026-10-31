import CoreGraphics

/// Where the app's icon goes on a window's picture: on frosted glass over the
/// window's own close, minimize and zoom buttons, at its left edge, the way
/// Windows always shows the app's icon at a window's top-left corner. The
/// buttons cannot be pressed in a picture, and a row of them says nothing.
///
/// The plate scales with the window, so it covers the buttons at any size; the
/// icon does not shrink with it below `minIconSide`, or a big window in a small
/// card would leave only a speck where its icon should be.
struct ThumbnailCover: Equatable {
    /// The frosted plate, from the picture's top-left corner.
    let plate: CGSize
    /// The icon's width and height.
    let iconSide: CGFloat
    /// The icon's top-left corner inside the plate.
    let iconOrigin: CGPoint

    /// The area the buttons sit in, in window points: wide enough for all three,
    /// tall enough for a title bar or a tall macOS 26 toolbar.
    static let buttonArea = CGSize(width: 86, height: 52)
    /// The icon's share of the button area's height when the picture is big.
    static let iconShare: CGFloat = 0.6
    /// The smallest icon that still reads as the app's.
    static let minIconSide: CGFloat = 14
    /// In a tiny picture the icon takes at most this share of its shorter side.
    static let maxPictureShare: CGFloat = 0.35

    /// The cover for a picture shown at `picture` size of a window of `window`
    /// size, in points; nil without both sizes.
    static func layout(picture: CGSize, window: CGSize) -> ThumbnailCover? {
        guard window.width > 0, picture.width > 0, picture.height > 0 else { return nil }
        let scale = picture.width / window.width
        let area = CGSize(width: buttonArea.width * scale, height: buttonArea.height * scale)
        let readable = max(area.height * iconShare, minIconSide)
        let icon = min(readable, min(picture.width, picture.height) * maxPictureShare)
        // The same margin above, below and left of the icon, so it sits at the
        // plate's left edge, over the close button.
        let margin = max((area.height - icon) / 2, icon * 0.2)
        let plate = CGSize(
            width: min(max(area.width, icon + 2 * margin), picture.width),
            height: min(max(area.height, icon + 2 * margin), picture.height)
        )
        return ThumbnailCover(plate: plate, iconSide: icon, iconOrigin: CGPoint(x: margin, y: margin))
    }
}
