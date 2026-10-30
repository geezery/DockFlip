import AppKit
import Testing
@testable import DockFlipKit

/// Thumbnails switched on without Screen Recording also show in the menu bar menu,
/// for whoever never opens Settings again after setup; the item opens Settings.
@Suite("Menu: Screen Recording warning")
@MainActor
struct StatusMenuScreenRecordingTests {
    @Test func onlyWhileWaitingForPermission() {
        #expect(StatusMenu.screenRecordingWarning(.off, openSettings: {}) == nil)
        #expect(StatusMenu.screenRecordingWarning(.on, openSettings: {}) == nil)

        let item = StatusMenu.screenRecordingWarning(.waitingForPermission, openSettings: {})
        #expect(item?.title == L("Screen Recording is not allowed yet"))
        #expect(item?.subtitle == L("Window thumbnails are not shown"))
        #expect(item?.isEnabled == true)
    }

    @Test func clickOpensSettings() throws {
        var opened = 0
        let item = try #require(StatusMenu.screenRecordingWarning(.waitingForPermission) { opened += 1 })
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)

        _ = target.perform(action, with: item)
        #expect(opened == 1)
    }
}
