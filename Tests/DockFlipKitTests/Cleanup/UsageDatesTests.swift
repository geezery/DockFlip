import Foundation
import Testing
@testable import DockFlipKit

@Suite("UsageDates")
struct UsageDatesTests {
    let then = Date(timeIntervalSince1970: 1_800_000_000)
    let now = Date(timeIntervalSince1970: 1_800_090_000)

    @Test func newWindowsCountFromNowAndKnownOnesKeepTheirDate() {
        var dates: [UInt32: Date] = [1: then]
        UsageDates.stamp(&dates, tracked: [1, 2, 3], active: nil, now: now)
        #expect(dates == [1: then, 2: now, 3: now])
    }

    @Test func activeWindowIsUsedNow() {
        var dates: [UInt32: Date] = [1: then, 2: then]
        UsageDates.stamp(&dates, tracked: [1, 2], active: 2, now: now)
        #expect(dates == [1: then, 2: now])
    }

    /// A window drag sends a stream of changes with nothing new: the dates stay put.
    @Test func repeatedChangesWithNothingNewChangeNothing() {
        var dates: [UInt32: Date] = [1: then, 2: then]
        for step in 1...50 {
            UsageDates.stamp(&dates, tracked: [1, 2], active: nil, now: now.addingTimeInterval(Double(step)))
        }
        #expect(dates == [1: then, 2: then])
    }

    /// Dates of windows the registry no longer tracks stay until `save()` asks the
    /// window server which windows still exist.
    @Test func untrackedWindowsKeepTheirDate() {
        var dates: [UInt32: Date] = [1: then, 9: then]
        UsageDates.stamp(&dates, tracked: [1], active: 1, now: now)
        #expect(dates == [1: now, 9: then])
    }
}
