import AppKit

/// Remembers when each window and app was last used, for the cleaner.
/// Driven by the registry's change notifications — no polling. Survives Plinth
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

    /// When the window was last focused. Windows first seen by Plinth count from then.
    func lastUsed(window id: CGWindowID) -> Date {
        windowLastUsed[id] ?? Date()
    }

    func lastUsed(app: NSRunningApplication) -> Date {
        let used = appLastUsed[Self.key(for: app)] ?? .distantPast
        let launched = app.launchDate ?? .distantPast
        let latest = max(used, launched)
        return latest == .distantPast ? Date() : latest
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

    private func update() {
        let now = Date()
        for window in registry.currentSpaceWindows() where windowLastUsed[window.id] == nil {
            windowLastUsed[window.id] = now
        }
        if let active = registry.activeWindowID() {
            windowLastUsed[active] = now
            if active != lastActive {
                lastActive = active
                scheduleSave()
            }
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
        let alive = Set(Self.allWindowIDs())
        windowLastUsed = windowLastUsed.filter { alive.contains($0.key) }

        let defaults = UserDefaults.standard
        defaults.set(Dictionary(uniqueKeysWithValues: windowLastUsed.map { (String($0.key), $0.value.timeIntervalSince1970) }), forKey: Key.windows)
        defaults.set(appLastUsed.mapValues { $0.timeIntervalSince1970 }, forKey: Key.apps)
        defaults.set(Self.bootTime(), forKey: Key.boot)
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let apps = defaults.dictionary(forKey: Key.apps) as? [String: Double] {
            appLastUsed = apps.mapValues { Date(timeIntervalSince1970: $0) }
        }
        // Window ids are reused after a restart; only trust them from this boot.
        guard abs(defaults.double(forKey: Key.boot) - Self.bootTime()) < 2,
              let stored = defaults.dictionary(forKey: Key.windows) as? [String: Double] else { return }
        for (key, value) in stored {
            if let id = UInt32(key) { windowLastUsed[CGWindowID(id)] = Date(timeIntervalSince1970: value) }
        }
    }

    static func bootTime() -> TimeInterval {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0 else { return 0 }
        return TimeInterval(time.tv_sec)
    }

    /// Ids of every normal-layer window on every Space, minimized included.
    static func allWindowIDs() -> [CGWindowID] {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber else { return nil }
            return CGWindowID(number.uint32Value)
        }
    }

    /// Pids that own at least one real (normal-layer, non-tiny) window on any Space.
    static func pidsWithWindows() -> Set<pid_t> {
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var pids = Set<pid_t>()
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 80, bounds.height >= 60 else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { continue }
            pids.insert(pid_t(pid.int32Value))
        }
        return pids
    }
}
