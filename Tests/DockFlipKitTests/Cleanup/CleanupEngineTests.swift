import Foundation
import Testing
@testable import DockFlipKit

@Suite("CleanupEngine")
struct CleanupEngineTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 24 * 3600

    @Test func suggestsOnlyLongUnusedWindowsOldestFirst() {
        let windows = [
            CleanupEngine.WindowInput(id: 1, bundleID: "com.microsoft.teams2", lastUsed: now.addingTimeInterval(-5 * day)),
            CleanupEngine.WindowInput(id: 2, bundleID: "com.apple.Safari", lastUsed: now.addingTimeInterval(-1 * day)),
            CleanupEngine.WindowInput(id: 3, bundleID: "com.apple.Preview", lastUsed: now.addingTimeInterval(-9 * day))
        ]
        #expect(CleanupEngine.idleWindows(windows, now: now, keep: []) == [3, 1])
        #expect(CleanupEngine.idleWindows(windows, now: now, keep: ["com.apple.Preview"]) == [1])
    }

    @Test func suggestsWindowlessAppsButNeverFinderOrFrontmost() {
        let old = now.addingTimeInterval(-2 * day)
        let apps = [
            CleanupEngine.AppInput(pid: 10, bundleID: "com.apple.finder", hasWindows: false, isFrontmost: false, lastUsed: old),
            CleanupEngine.AppInput(pid: 11, bundleID: "com.apple.TextEdit", hasWindows: false, isFrontmost: false, lastUsed: old),
            CleanupEngine.AppInput(pid: 12, bundleID: "com.apple.Notes", hasWindows: true, isFrontmost: false, lastUsed: old),
            CleanupEngine.AppInput(pid: 13, bundleID: "com.apple.Music", hasWindows: false, isFrontmost: true, lastUsed: old),
            CleanupEngine.AppInput(pid: 14, bundleID: "com.apple.Maps", hasWindows: false, isFrontmost: false, lastUsed: now)
        ]
        #expect(CleanupEngine.idleApps(apps, now: now, keep: []) == [11])
    }
}
