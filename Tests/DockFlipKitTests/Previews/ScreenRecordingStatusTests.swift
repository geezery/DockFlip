import Testing
@testable import DockFlipKit

/// Thumbnails switched on without Screen Recording show a warning in Settings,
/// and the answer is read again when Settings asks (after System Settings or a restart).
@Suite("Thumbnails: Screen Recording")
@MainActor
struct ScreenRecordingStatusTests {
    @Test func onWithoutPermissionWaits() {
        #expect(ThumbnailAccess(enabled: true, screenRecordingAllowed: false) == .waitingForPermission)
        #expect(ThumbnailAccess(enabled: true, screenRecordingAllowed: true) == .on)
        #expect(ThumbnailAccess(enabled: false, screenRecordingAllowed: false) == .off)
        #expect(ThumbnailAccess(enabled: false, screenRecordingAllowed: true) == .off)
    }

    @Test func refreshReadsTheAnswerAgain() {
        var allowed = false
        let status = ScreenRecordingStatus(check: { allowed })
        #expect(!status.isAllowed)

        allowed = true
        #expect(!status.isAllowed)
        status.refresh()
        #expect(status.isAllowed)

        allowed = false
        status.refresh()
        #expect(!status.isAllowed)
    }
}
