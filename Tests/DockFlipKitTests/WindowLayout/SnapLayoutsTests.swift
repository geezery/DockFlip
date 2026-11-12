import CoreGraphics
import Testing
@testable import DockFlipKit

@Suite("SnapLayouts")
struct SnapLayoutsTests {
    // A 1440 x 900 display under a 33 pt menu bar, AX space.
    let area = CGRect(x: 0, y: 33, width: 1440, height: 867)

    @Test func everyLayoutCoversTheAreaOnceOver() {
        for layout in SnapLayouts.all {
            let cells = layout.zones.reduce(0) { $0 + $1.width * $1.height }
            #expect(cells == LayoutZone.columns * LayoutZone.rows)
            let total = layout.zones.reduce(CGFloat(0)) { sum, zone in
                let rect = SnapLayouts.rect(for: zone, in: area)
                return sum + rect.width * rect.height
            }
            #expect(total == area.width * area.height)
        }
    }

    @Test func thirdsAreExactAndShareTheirEdges() {
        let thirds = SnapLayouts.all[4].zones.map { SnapLayouts.rect(for: $0, in: area) }
        #expect(thirds.map(\.width) == [480, 480, 480])
        #expect(thirds[0].maxX == thirds[1].minX)
        #expect(thirds[1].maxX == thirds[2].minX)
        #expect(thirds[2].maxX == area.maxX)
    }

    @Test func halvesAndQuartersAgreeWithTheEdgeSnaps() {
        let odd = CGRect(x: 1440, y: 25, width: 1513, height: 957)
        let halves = SnapLayouts.all[0].zones.map { SnapLayouts.rect(for: $0, in: odd) }
        #expect(halves[0] == SnapEngine.rect(for: .leftHalf, in: odd))
        #expect(halves[1] == SnapEngine.rect(for: .rightHalf, in: odd))
        let quarters = SnapLayouts.all[3].zones.map { SnapLayouts.rect(for: $0, in: odd) }
        #expect(quarters == [SnapEngine.rect(for: .topLeft, in: odd), SnapEngine.rect(for: .topRight, in: odd),
                             SnapEngine.rect(for: .bottomLeft, in: odd), SnapEngine.rect(for: .bottomRight, in: odd)])
    }

    @Test func aFrameInAZoneIsFoundWithTolerance() {
        let twoThirds = LayoutZone(column: 0, width: 8)
        // A terminal that rounds its width to whole characters.
        let frame = CGRect(x: 0, y: 33, width: 952, height: 860)
        #expect(SnapLayouts.zone(matching: frame, in: area) == twoThirds)
        #expect(SnapLayouts.zone(matching: CGRect(x: 200, y: 200, width: 700, height: 500), in: area) == nil)
    }

    @Test func snapAssistOffersTheNextZoneRound() {
        let halfAndQuarters = SnapLayouts.all[2]
        #expect(SnapLayouts.nextZone(in: halfAndQuarters, after: 0) == halfAndQuarters.zones[1])
        #expect(SnapLayouts.nextZone(in: halfAndQuarters, after: 2) == halfAndQuarters.zones[0])
        #expect(SnapLayouts.nextZone(in: SnapLayout(zones: [LayoutZone(column: 0, width: 12)]), after: 0) == nil)
    }
}
