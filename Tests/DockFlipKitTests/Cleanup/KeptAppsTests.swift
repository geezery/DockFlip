import CoreGraphics
import Foundation
import Testing
@testable import DockFlipKit

@Suite("Clean Up Keep")
struct KeptAppsTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    /// "Keep" on one Safari window hides only that window: another idle Safari
    /// window is still suggested, and so is the kept one once it idles again.
    @Test func keepOnOneWindowHidesOnlyThatWindow() {
        var dates: [CGWindowID: Date] = [1: now.addingTimeInterval(-5 * day), 2: now.addingTimeInterval(-4 * day)]
        UsageDates.keep(&dates, id: 1, now: now)

        func suggested(at time: Date) -> [CGWindowID] {
            let windows = dates.map { CleanupEngine.WindowInput(id: $0.key, bundleID: "com.apple.Safari", lastUsed: $0.value) }
            return CleanupEngine.idleWindows(windows, now: time, keep: [])
        }
        #expect(suggested(at: now) == [2])
        #expect(suggested(at: now.addingTimeInterval(3 * day)) == [2, 1])
    }

    /// "Never suggest this app again" hides every window of the app; removing it
    /// from the kept apps brings them back.
    @Test func removingAKeptAppSuggestsItAgain() {
        let old = now.addingTimeInterval(-5 * day)
        let windows = [
            CleanupEngine.WindowInput(id: 1, bundleID: "com.apple.Safari", lastUsed: old),
            CleanupEngine.WindowInput(id: 2, bundleID: "com.apple.Safari", lastUsed: old),
            CleanupEngine.WindowInput(id: 3, bundleID: "com.apple.Preview", lastUsed: old)
        ]
        var kept = KeptApps([])
        kept.add("com.apple.Safari")
        #expect(CleanupEngine.idleWindows(windows, now: now, keep: kept.set) == [3])

        kept.remove("com.apple.Safari")
        #expect(kept.bundleIDs.isEmpty)
        #expect(Set(CleanupEngine.idleWindows(windows, now: now, keep: kept.set)) == [1, 2, 3])
    }

    /// The stored list stays sorted with each app once, whatever was stored before.
    @Test func keptAppsAreStoredSortedAndOnce() {
        var kept = KeptApps(["com.apple.Safari", "com.apple.Notes", "com.apple.Safari"])
        #expect(kept.bundleIDs == ["com.apple.Notes", "com.apple.Safari"])
        kept.add("com.apple.Maps")
        kept.add("com.apple.Notes")
        #expect(kept.bundleIDs == ["com.apple.Maps", "com.apple.Notes", "com.apple.Safari"])
        kept.remove("com.apple.Music")
        #expect(kept.bundleIDs.count == 3)
    }
}
