import Combine
import CoreGraphics

/// What the thumbnails switch amounts to, given macOS's Screen Recording answer.
enum ThumbnailAccess: Equatable {
    /// The user switched thumbnails off.
    case off
    /// Switched on and allowed: windows are pictured.
    case on
    /// Switched on, but macOS has not allowed Screen Recording: nothing is pictured.
    case waitingForPermission

    init(enabled: Bool, screenRecordingAllowed: Bool) {
        if !enabled {
            self = .off
        } else {
            self = screenRecordingAllowed ? .on : .waitingForPermission
        }
    }
}

/// Whether macOS lets DockFlip record the screen, for views that show it.
///
/// macOS asks in its own prompt, which the user may deny, and after the switch is
/// turned on in System Settings it often applies only once DockFlip restarts. The
/// answer is read again when asked (Settings does when its window comes forward),
/// never on a timer.
@MainActor
final class ScreenRecordingStatus: ObservableObject {
    @Published private(set) var isAllowed: Bool
    private let check: () -> Bool

    /// `check` is for tests; it defaults to asking macOS.
    init(check: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.check = check
        isAllowed = check()
    }

    func refresh() {
        let allowed = check()
        if allowed != isAllowed { isAllowed = allowed }
    }
}
