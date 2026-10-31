import Testing
@testable import DockFlipKit

@Suite("SwitcherStyle")
struct SwitcherStyleTests {
    @Test func storedStyleFallsBackToFlip3D() {
        #expect(SwitcherStyle(stored: "grid") == .grid)
        #expect(SwitcherStyle(stored: "flip3D") == .flip3D)
        // Nothing stored, or a name this DockFlip does not know (a newer version's, a typo in a profile).
        #expect(SwitcherStyle(stored: nil) == .flip3D)
        #expect(SwitcherStyle(stored: "Grid") == .flip3D)
        #expect(SwitcherStyle(stored: "") == .flip3D)
    }
}
