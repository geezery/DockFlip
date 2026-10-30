import Foundation

/// Tells setup when the Accessibility permission changes, without a repeating timer
/// (CONTRIBUTING.md, rule 3). Setup calls `check()` when the app or its window comes back
/// to the front, and `settingsChanged()` when macOS announces that the Accessibility list
/// changed (`com.apple.accessibility.api`).
@MainActor
final class AccessibilityWatch {
    /// How long after the announcement to ask again. It comes when any app's switch flips,
    /// and `AXIsProcessTrusted()` can still give the old answer for a moment after it, so
    /// one look is not enough. The first look is well inside a second; the series ends
    /// after the last one, so nothing keeps running while setup sits open.
    static let rechecks: [Duration] = [.milliseconds(300), .seconds(1), .seconds(3)]

    private(set) var granted: Bool
    /// Called on the main actor with the new answer, only when it changes.
    var onChange: ((Bool) -> Void)?

    private let isTrusted: @MainActor () -> Bool
    private let sleep: @MainActor (Duration) async -> Void
    private var rechecking: Task<Void, Never>?

    /// Tests pass their own `isTrusted` and an instant `sleep`.
    init(
        isTrusted: @escaping @MainActor () -> Bool = { Permissions.isAccessibilityTrusted },
        sleep: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.isTrusted = isTrusted
        self.sleep = sleep
        granted = isTrusted()
    }

    /// Asks macOS once and reports a change.
    func check() {
        let now = isTrusted()
        guard now != granted else { return }
        granted = now
        onChange?(now)
    }

    /// The Accessibility list changed: ask again at each of `rechecks`, and stop early once
    /// the answer changes. A newer announcement starts the series over.
    @discardableResult
    func settingsChanged() -> Task<Void, Never> {
        rechecking?.cancel()
        let before = granted
        let task = Task { [weak self] in
            for delay in AccessibilityWatch.rechecks {
                await self?.sleep(delay)
                guard !Task.isCancelled, let self else { return }
                self.check()
                if self.granted != before { return }
            }
        }
        rechecking = task
        return task
    }

    /// Setup closed: drop a series still waiting.
    func stop() {
        rechecking?.cancel()
        rechecking = nil
    }
}
