import CoreGraphics
import Testing
@testable import DockFlipKit

/// The app's icon over a window's close, minimize and zoom buttons in its
/// picture, as Windows shows the app's icon at every window's top-left corner.
@Suite("ThumbnailCover: the app's icon over the window buttons")
struct ThumbnailCoverTests {
    let window = CGSize(width: 1440, height: 900)

    func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

    /// The buttons' area as it shows in a picture `width` points wide.
    func buttons(atWidth width: CGFloat) -> CGSize {
        let scale = width / window.width
        return CGSize(width: ThumbnailCover.buttonArea.width * scale, height: ThumbnailCover.buttonArea.height * scale)
    }

    @Test func bigPictureScalesWithTheWindow() throws {
        // ⌘Tab's front card: half the window's size.
        let cover = try #require(ThumbnailCover.layout(picture: CGSize(width: 720, height: 450), window: window))
        #expect(close(cover.plate.width, 43))
        #expect(close(cover.plate.height, 26))
        #expect(close(cover.iconSide, 15.6))
        #expect(close(cover.iconOrigin.x, 5.2))
        #expect(close(cover.iconOrigin.y, 5.2))
    }

    @Test func smallPictureKeepsTheIconReadable() throws {
        // A Dock list card: the window's own icon area would be under 4 points.
        let picture = CGSize(width: 179, height: 112)
        let cover = try #require(ThumbnailCover.layout(picture: picture, window: window))
        #expect(close(cover.iconSide, ThumbnailCover.minIconSide))
        let area = buttons(atWidth: picture.width)
        #expect(cover.plate.width >= area.width)
        #expect(cover.plate.height >= area.height)
    }

    @Test func plateAlwaysCoversTheButtonsAndHoldsTheIcon() throws {
        for width in [60.0, 120, 179, 280, 480, 720, 1000, 1440] as [CGFloat] {
            let picture = CGSize(width: width, height: width * window.height / window.width)
            let cover = try #require(ThumbnailCover.layout(picture: picture, window: window))
            let area = buttons(atWidth: width)
            #expect(cover.plate.width >= area.width - 0.001, "width \(width)")
            #expect(cover.plate.height >= area.height - 0.001, "width \(width)")
            #expect(cover.iconOrigin.x + cover.iconSide <= cover.plate.width + 0.001, "width \(width)")
            #expect(cover.iconOrigin.y + cover.iconSide <= cover.plate.height + 0.001, "width \(width)")
        }
    }

    @Test func iconSitsAtTheLeftEdge() throws {
        let cover = try #require(ThumbnailCover.layout(picture: CGSize(width: 720, height: 450), window: window))
        // Over the close button: as far from the left as from the top, in the plate's left half.
        #expect(close(cover.iconOrigin.x, cover.iconOrigin.y))
        #expect(cover.iconOrigin.x + cover.iconSide / 2 < cover.plate.width / 2)
    }

    @Test func tinyPictureIsNotSwampedByTheIcon() throws {
        let picture = CGSize(width: 32, height: 20)
        let cover = try #require(ThumbnailCover.layout(picture: picture, window: window))
        #expect(cover.iconSide <= 20 * ThumbnailCover.maxPictureShare + 0.001)
        #expect(cover.plate.width <= picture.width)
        #expect(cover.plate.height <= picture.height)
    }

    @Test func noCoverWithoutSizes() {
        #expect(ThumbnailCover.layout(picture: CGSize(width: 200, height: 120), window: .zero) == nil)
        #expect(ThumbnailCover.layout(picture: .zero, window: window) == nil)
    }
}
