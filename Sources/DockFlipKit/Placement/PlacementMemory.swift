import AppKit

/// Windows 11's "Remember window locations based on monitor connection":
/// remembers where every window was for each set of displays, and puts the
/// windows back when that set of displays is connected again. The layouts survive
/// DockFlip restarts, until the Mac restarts (see `PlacementLayouts`).
@MainActor
final class PlacementMemory {
    private let registry: WindowRegistry
    private var layouts = PlacementLayouts()
    /// What UserDefaults holds now, so an unchanged save writes nothing.
    private var storedLayouts = PlacementLayouts()
    private var currentSignature = ""
    /// Saving pauses while macOS shuffles windows after a display change.
    private var pausedUntil = Date.distantPast
    private var saveTask: Task<Void, Never>?
    private var tokens: [NSObjectProtocol] = []

    private enum Key {
        static let layouts = "placement.layouts"
        static let boot = "placement.bootTime"
    }

    init(registry: WindowRegistry) {
        self.registry = registry
    }

    func start() {
        load()
        currentSignature = Self.signature()
        registry.addObserver { [weak self] in self?.scheduleSave() }
        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.displaysChanged() }
        })
        // Started with other displays than the last save was for (restarted mid-change, or
        // the displays changed while DockFlip wasn't running): treat it as the change, so
        // macOS's shuffle isn't saved over the layout remembered for these displays.
        if layouts.isDisplayChange(to: currentSignature) {
            Log.app.notice("Started after a display change")
            settle()
        }
        saveNow() // waits out the pause by itself
    }

    // MARK: - Display changes

    private func displaysChanged() {
        let signature = Self.signature()
        guard signature != currentSignature else { return }
        let screenCount = NSScreen.screens.count
        Log.app.notice("Displays changed: \(screenCount, privacy: .public) screen(s)")
        currentSignature = signature
        settle()
    }

    /// Pauses saving while macOS moves windows for the displays now connected, then puts
    /// back the layout remembered for them.
    private func settle() {
        let signature = currentSignature
        pausedUntil = Date().addingTimeInterval(4)
        saveTask?.cancel()
        saveTask = nil

        guard let layout = layouts[signature] else { return }
        // Give macOS a moment to finish moving windows itself, then put them back.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.currentSignature == signature else { return }
            self.restore(layout)
        }
    }

    private func restore(_ layout: [CGWindowID: CGRect]) {
        let start = Perf.now()
        let screens = NSScreen.screens.map { DisplayLayout.axFrame(of: $0) }
        // Frames from memory (kept current by moved/resized notifications), so a hung app
        // can't stall the main thread and its event taps; setFrame itself runs on AppQueues.
        var known: [CGWindowID: PlacementRestore.Known] = [:]
        for id in layout.keys {
            guard let window = registry.window(id), !window.isMinimized else { continue }
            if let frame = registry.knownFrame(of: id) {
                known[id] = .frame(frame)
            } else {
                known[id] = .unknownFrame
            }
        }
        let moves = PlacementRestore.moves(layout: layout, screens: screens, known: known)
        for move in moves { registry.setFrame(of: move.id, to: move.frame) }
        let moved = moves.count
        Perf.shared.record("placement.restore", since: start, detail: "\(moved) windows")
        Log.app.notice("Restored \(moved, privacy: .public) window positions")
    }

    // MARK: - Saving

    private func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.saveNow()
        }
    }

    private func saveNow() {
        guard Date() >= pausedUntil else {
            scheduleSave()
            return
        }
        // Only save for the display set that is really connected now.
        let signature = Self.signature()
        guard signature == currentSignature else { return }

        let screens = NSScreen.screens.map { DisplayLayout.axFrame(of: $0) }
        var layout = layouts[signature] ?? [:]
        for window in registry.currentSpaceWindows() where !window.isMinimized && !window.isAppHidden {
            guard screens.contains(where: { $0.intersects(window.frame) }),
                  !screens.contains(where: { $0 == window.frame }) else { continue } // skip full-screen
            layout[window.id] = window.frame
        }
        layouts.set(layout, for: signature)
        // Forget windows that are gone. An empty list is a failed read, not an answer.
        let alive = Set(WindowServer.windows(onScreenOnly: false).map(\.id))
        if !alive.isEmpty { layouts.keepOnly(alive) }
        store()
    }

    /// Call when the app quits, so the last moves are kept for the next launch.
    func saveOnQuit() {
        saveTask?.cancel()
        saveTask = nil
        // Mid display change the frames are macOS's shuffle, not the user's layout.
        guard Date() >= pausedUntil else { return }
        saveNow()
    }

    // MARK: - Across restarts

    private func store() {
        guard layouts != storedLayouts else { return }
        let defaults = UserDefaults.standard
        defaults.set(layouts.propertyList, forKey: Key.layouts)
        defaults.set(BootTime.now(), forKey: Key.boot)
        storedLayouts = layouts
    }

    private func load() {
        let defaults = UserDefaults.standard
        guard BootTime.isSameBoot(saved: defaults.double(forKey: Key.boot)) else { return }
        layouts = PlacementLayouts(propertyList: defaults.array(forKey: Key.layouts))
        storedLayouts = layouts
        Log.app.notice("Loaded window positions for \(self.layouts.order.count, privacy: .public) display set(s)")
    }

    /// Identifies the connected set of displays and how they are arranged.
    static func signature() -> String {
        NSScreen.screens.map { screen -> String in
            let id = DisplayLayout.displayID(of: screen)
            var name = "\(id)"
            if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
                name = CFUUIDCreateString(nil, uuid) as String
            }
            let f = screen.frame
            return "\(name)@\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width))x\(Int(f.height))"
        }
        .sorted()
        .joined(separator: "|")
    }
}
