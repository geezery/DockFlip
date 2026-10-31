import ApplicationServices
import Testing
@testable import DockFlipKit

/// `AXUIElement.frame(position:size:)` is the one decoder both frame reads use:
/// a window read alone and a window read in a batch.
@Suite("AX frame decode")
struct AXFrameDecodeTests {
    private func point(_ x: CGFloat, _ y: CGFloat) -> CFTypeRef {
        var value = CGPoint(x: x, y: y)
        return AXValueCreate(.cgPoint, &value)!
    }

    private func size(_ width: CGFloat, _ height: CGFloat) -> CFTypeRef {
        var value = CGSize(width: width, height: height)
        return AXValueCreate(.cgSize, &value)!
    }

    @Test func decodesPositionAndSize() {
        #expect(AXUIElement.frame(position: point(10, -20), size: size(300, 200))
                == CGRect(x: 10, y: -20, width: 300, height: 200))
    }

    @Test func missingValueIsNoFrame() {
        #expect(AXUIElement.frame(position: nil, size: size(1, 1)) == nil)
        #expect(AXUIElement.frame(position: point(1, 1), size: nil) == nil)
    }

    @Test func wrongTypeIsNoFrame() {
        // A batch read answers a missing attribute with an error AXValue, and
        // anything else (a string) is no frame either.
        var error = AXError.attributeUnsupported
        let errorValue = AXValueCreate(.axError, &error)!
        #expect(AXUIElement.frame(position: errorValue, size: size(1, 1)) == nil)
        #expect(AXUIElement.frame(position: size(1, 1), size: point(1, 1)) == nil)
        #expect(AXUIElement.frame(position: "x" as CFString, size: size(1, 1)) == nil)
    }
}
