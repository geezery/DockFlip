import Foundation
import Testing
@testable import DockFlipKit

@Suite("DockAppOrder")
struct DockAppOrderTests {
    /// A Dock as the AX tree lists it: apps, then a separator, a folder and the Trash.
    private let dock: [String?] = ["com.apple.finder", nil, "com.apple.Safari", "com.apple.mail", nil, nil, nil]

    // MARK: - The n-th app

    @Test func countsOnlyApps() {
        #expect(DockAppOrder.app(at: 0, in: dock) { $0 } == "com.apple.finder")
        #expect(DockAppOrder.app(at: 1, in: dock) { $0 } == "com.apple.Safari")
        #expect(DockAppOrder.app(at: 2, in: dock) { $0 } == "com.apple.mail")
    }

    @Test func readsTheIconsOnlyUpToTheApp() {
        // The first app needs one icon read, not the whole Dock.
        var reads = 0
        let first = DockAppOrder.app(at: 0, in: dock) { reads += 1; return $0 }
        #expect(first == "com.apple.finder")
        #expect(reads == 1)

        reads = 0
        _ = DockAppOrder.app(at: 1, in: dock) { reads += 1; return $0 }
        #expect(reads == 3)
    }

    @Test func noAppPastTheLast() {
        #expect(DockAppOrder.app(at: 3, in: dock) { $0 } == nil)
        #expect(DockAppOrder.app(at: 8, in: dock) { $0 } == nil)
        #expect(DockAppOrder.app(at: 0, in: [String?]()) { $0 } == nil)
    }

    @Test func noAppForANegativeIndex() {
        #expect(DockAppOrder.app(at: -1, in: dock) { $0 } == nil)
    }

    // MARK: - Bundle IDs by URL

    private let safari = URL(fileURLWithPath: "/Applications/Safari.app")

    @Test func readsEachAppOnce() {
        var cache = BundleIDCache()
        var reads = 0
        for _ in 0..<3 {
            let id = cache.bundleID(for: safari) { _ in reads += 1; return "com.apple.Safari" }
            #expect(id == "com.apple.Safari")
        }
        #expect(reads == 1)
    }

    @Test func aFailedReadIsTriedAgain() {
        var cache = BundleIDCache()
        #expect(cache.bundleID(for: safari) { _ in nil } == nil)
        #expect(cache.bundleID(for: safari) { _ in "com.apple.Safari" } == "com.apple.Safari")
    }
}
