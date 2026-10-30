import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("Geometry")
struct GeometryTests {
    // Primary 1440×900 at the origin, a second 1920×1080 display to its right,
    // bottom-aligned (Cocoa coordinates).
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let secondary = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test func cocoaToAXRoundTrip() {
        let ax = Geometry.axRect(fromCocoa: secondary, primaryHeight: primary.height)
        #expect(ax == CGRect(x: 1440, y: -180, width: 1920, height: 1080))
        #expect(Geometry.cocoaRect(fromAX: ax, primaryHeight: primary.height) == secondary)
    }

    @Test func picksScreenWithMostOverlap() {
        let screens = [primary, secondary].map { Geometry.axRect(fromCocoa: $0, primaryHeight: primary.height) }
        let window = CGRect(x: 1300, y: 100, width: 800, height: 600)
        #expect(Geometry.bestScreenIndex(for: window, screens: screens) == 1)
        #expect(Geometry.bestScreenIndex(for: CGRect(x: -5000, y: 0, width: 10, height: 10), screens: screens) == nil)
    }

    @Test func normalizesWithinScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 500)
        let rect = Geometry.normalized(CGRect(x: 0, y: 0, width: 500, height: 500), in: screen)
        #expect(rect == CGRect(x: 0, y: 0, width: 0.5, height: 1))
    }
}
