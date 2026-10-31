import Foundation

/// Attaches to the Dock, and tries again a few times when that fails, without a
/// repeating timer (CONTRIBUTING.md, rule 3).
///
/// Right after login, or while the Dock relaunches after a settings change, its
/// Accessibility tree can be missing the icon list for a moment. One failed look
/// used to leave hover lists and the click takeover off until DockFlip restarted.
@MainActor
final class DockAttachRetry {
    /// How long to wait before each further try after a failed one. The series ends
    /// with the last try, success or not, so nothing keeps running against a Dock
    /// that never shows its list; the next Dock relaunch starts it over.
    static let delays: [Duration] = [.seconds(1), .seconds(2), .seconds(4)]

    private let sleep: @MainActor (Duration) async -> Void
    private var retrying: Task<Void, Never>?

    /// Tests pass an instant `sleep`.
    init(sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    /// Tries `attach` now and, while it fails, again after each of `delays`. A newer
    /// call drops a series still waiting and starts over. Returns the series, or nil
    /// when the first try worked.
    /// - attach: true when it attached.
    @discardableResult
    func start(_ attach: @escaping @MainActor () -> Bool) -> Task<Void, Never>? {
        stop()
        if attach() { return nil }
        // The series holds only the wait and the attach, not this object: the
        // attach itself says when its owner is gone (it answers true).
        let sleep = self.sleep
        let task = Task { @MainActor in
            for delay in DockAttachRetry.delays {
                await sleep(delay)
                guard !Task.isCancelled else { return }
                if attach() { return }
            }
        }
        retrying = task
        return task
    }

    /// Drops a series still waiting.
    func stop() {
        retrying?.cancel()
        retrying = nil
    }
}
