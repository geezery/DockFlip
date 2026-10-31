import AppKit

/// Remembers when each window and app was last used, for the cleaner.
/// Driven by the registry's change notifications — no polling. Survives DockFlip
/// restarts (window ids stay valid until the Mac restarts, so the data is tied
/// to the boot time).
@MainActor
final class UsageTracker {
    private let registry: WindowRegistry
    private(set) var windowLastUsed: [CGWindowID: Date] = [:]
    private var appLastUsed: [String: Date] = [:]
    private var lastActive: CGWindowID?
    private var saveTask: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []

    private enum Key {
        static let windows = "usage.windowLastUsed"
        static let apps = "usage.appLastUsed"
        static let boot = "usage.bootTime"
    }

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    func start() {
        load()
        registry.addObserver { [weak self] in self?.update() }
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app else { return }
                self.appLastUsed[Self.key(for: app)] = Date()
                self.scheduleSave()
            }
        })
        update()
    }

    /// When the window was last focused. Windows first seen by DockFlip count from then.
    func lastUsed(window id: CGWindowID) -> Date {
        windowLastUsed[id] ?? Date()
    }

    func lastUsed(app: NSRunningApplication) -> Date {
        let used = appLastUsed[Self.key(for: app)] ?? .distantPast
        let launched = app.launchDate ?? .distantPast
        let latest = max(used, launched)
        return latest == .distantPast ? Date() : latest
    }

    /// Clean Up's "Keep" on a window row: this window counts as used now.
    func markUsed(window id: CGWindowID) {
        UsageDates.keep(&windowLastUsed, id: id, now: Date())
        scheduleSave()
    }

    /// Clean Up's "Keep" on an app row: the app counts as used now.
    func markUsed(app: NSRunningApplication) {
        appLastUsed[Self.key(for: app)] = Date()
        scheduleSave()
    }

    /// Call when the app quits so nothing is lost.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        save()
    }

    // MARK: - Private

    private static func key(for app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? "pid:\(app.processIdentifier)"
    }

    /// Runs after every registry change, a window drag's moves and resizes too, so it
    /// reads only the registry: no window server lists here (those wait for `save()`).
    private func update() {
        let active = registry.activeWindowID()
        UsageDates.stamp(&windowLastUsed, tracked: registry.trackedWindowIDs, active: active, now: Date())
        if let active, active != lastActive {
            lastActive = active
            scheduleSave()
        }
    }

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.save()
        }
    }

    private func save() {
        // Forget windows that no longer exist anywhere.
        let alive = Set(WindowServer.windows(onScreenOnly: false).map(\.id))
        windowLastUsed = windowLastUsed.filter { alive.contains($0.key) }

        let defaults = UserDefaults.standard
        defaults.set(Dictionary(uniqueKeysWithValues: windowLastUsed.map { (String($0.key), $0.value.timeIntervalSince1970) }), forKey: Key.windows)
        defaults.set(appLastUsed.mapValues { $0.timeIntervalSince1970 }, forKey: Key.apps)
        defaults.set(BootTime.now(), forKey: Key.boot)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let apps = defaults.dictionary(forKey: Key.apps) as? [String: Double] {
            appLastUsed = apps.mapValues { Date(timeIntervalSince1970: $0) }
        }
        // Window ids are reused after a restart; only trust them from this boot.
        guard BootTime.isSameBoot(saved: defaults.double(forKey: Key.boot)),
              let stored = defaults.dictionary(forKey: Key.windows) as? [String: Double] else { return }
        for (key, value) in stored {
            if let id = UInt32(key) { windowLastUsed[CGWindowID(id)] = Date(timeIntervalSince1970: value) }
        }
    }
}
