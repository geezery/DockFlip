import CoreGraphics
import Foundation
import Testing
@testable import DockFlipKit

/// SCOPE.md's ⌘Tab budget for the Windows 11 grid too, with 60 windows: the same
/// stage, items and limit as `SwitcherViewTimingTests`, only the look differs. The
/// grid draws a few rows around the selected tile (`SwitcherGrid.visibleRows`);
/// drawing all 60 tiles shows here. Needs a window server, as that suite does.
@Suite("SwitcherGridView timing")
@MainActor
struct SwitcherGridTimingTests {
    typealias Timing = SwitcherViewTimingTests

    @Test func sixtyWindowsOpenAndStepWithinTheBudget() {
        let stage = Timing.Stage(size: Timing.screen, style: .grid)
        defer { stage.close() }
        let apps = Timing.apps()
        let clock = ContinuousClock()
        stage.warmUp(Timing.items(60, apps: apps, firstID: 1))

        var opens: [Duration] = []
        var steps: [Duration] = []
        for round in 1...Timing.rounds {
            // Other windows each time, so every tile is built anew, not reused.
            let items = Timing.items(60, apps: apps, firstID: CGWindowID(round * 1000))
            opens.append(clock.measure { stage.open(items) })
            steps.append(clock.measure { stage.step() })
        }
        let opening = Timing.median(opens)
        let stepping = Timing.median(steps)
        let limit = Duration.milliseconds(Timing.budgetMs * Timing.ciAllowance)
        print("SwitcherGridView timing: 60 windows, open \(Timing.ms(opening)) ms, step \(Timing.ms(stepping)) ms "
              + "(limit \(Timing.ms(limit)) ms); medians of \(Timing.rounds)")

        let drawing: Duration = .milliseconds(1)
        #expect(opening > drawing, "Opening took \(Timing.ms(opening)) ms: nothing was drawn, so nothing was timed")
        #expect(opening < limit, "Opening the ⌘Tab grid with 60 windows took \(Timing.ms(opening)) ms, over \(Timing.ms(limit)) ms")
        #expect(stepping < limit, "A ⌘Tab grid step with 60 windows took \(Timing.ms(stepping)) ms, over \(Timing.ms(limit)) ms")
    }
}
