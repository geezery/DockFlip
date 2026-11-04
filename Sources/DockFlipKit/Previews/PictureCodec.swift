import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Packs the pictures kept in memory as HEIC and unpacks them at the size a view
/// needs. A 760-pixel picture is about 1.4 MB as a bitmap and some 50–80 kB as
/// HEIC, so dozens fit in a few megabytes. Every Mac that runs macOS 26 encodes
/// HEIC in hardware. Nothing here touches the disk.
enum PictureCodec {
    /// Lossy, but a window picture at this quality is indistinguishable at thumbnail size.
    static let quality = 0.6

    /// The picture as HEIC, or nil when ImageIO could not encode it (then the
    /// caller keeps the bitmap for this one picture).
    static func compress(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.heic.identifier as CFString, 1, nil) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// The picture with its longer side at most `maxPixelSize`, decoded now (not
    /// lazily at first draw, which would land on the main thread).
    static func decode(_ data: Data, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
}
