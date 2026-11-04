import CoreGraphics
import Testing
@testable import DockFlipKit

/// Pictures are kept packed as HEIC and unpacked at the size a view needs.
@Suite("Thumbnails: packing pictures")
struct PictureCodecTests {
    /// A 760×475 picture with something in it, as a window capture would be.
    private func picture() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 760, height: 475, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        context.setFillColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 760, height: 475))
        context.setFillColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 40, y: 40, width: 300, height: 200))
        return try #require(context.makeImage())
    }

    @Test func packsFarSmallerThanTheBitmap() throws {
        let image = try picture()
        let heic = try #require(PictureCodec.compress(image))
        #expect(heic.count < image.bytesPerRow * image.height / 10)
    }

    @Test func unpacksAtTheSizeAskedForAndNeverLarger() throws {
        let heic = try #require(PictureCodec.compress(try picture()))
        let small = try #require(PictureCodec.decode(heic, maxPixelSize: 400))
        #expect(small.width == 400)
        #expect(abs(small.height - 250) <= 1)
        let full = try #require(PictureCodec.decode(heic, maxPixelSize: 2000))
        #expect(full.width == 760)
        #expect(full.height == 475)
    }
}
