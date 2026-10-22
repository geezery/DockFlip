import AppKit
import Combine
import SwiftUI

/// One taskbar per display, drawn over the space the Dock reserves.
@MainActor
final class TaskbarController: PopupSource {
    private struct Bar {
        let panel: NSPanel
        let model: TaskbarModel
    }

    private let registry: WindowRegistry
    private let popup: TaskbarPopup
    private let calendar = CalendarFlyout()
    private var bars: [CGDirectDisplayID: Bar] = [:]
    private var iconCache: [String: NSImage] = [:]
    private var nameCache: [String: String] = [:]
    private var badges: [String: String] = [:]
    private var badgeTimer: Timer?
    private var tokens: [NSObjectProtocol] = []
    private var settingsSubscription: AnyCancellable?
    private var refreshPending = false
    private var dragHoverTask: Task<Void, Never>?
    private var dragHoverItem: String?

    init(registry: WindowRegistry) {
        self.registry = registry
        self.popup = TaskbarPopup(registry: registry)
        popup.source = self
    }

    func start() {
        layoutBars()
        registry.addObserver { [weak self] in self?.refresh() }

        tokens.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutBars() }
        })
        // Settings publish *before* they change; act on the next turn.
        settingsSubscription = Settings.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in self?.layoutBars() }
        }
        // Dock badges have no change notification. This is the one periodic task in
        // Plinth: a single cheap Accessibility read every 15 seconds.
        badgeTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBadges() }
        }
        refreshBadges()
    }

    // MARK: - Layout

    private func layoutBars() {
        let screens = Settings.shared.taskbarOnAllDisplays ? NSScreen.screens : Array(NSScreen.screens.prefix(1))
        let wanted = Set(screens.map { DisplayLayout.displayID(of: $0) })

        for (id, bar) in bars where !wanted.contains(id) {
            bar.panel.orderOut(nil)
            bars[id] = nil
        }
        for screen in screens {
            let id = DisplayLayout.displayID(of: screen)
            let bar = bars[id] ?? makeBar(displayID: id)
            bars[id] = bar
            let height = DisplayLayout.taskbarHeight(for: screen)
            if bar.model.barHeight != height { bar.model.barHeight = height }
            bar.panel.setFrame(
                NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height),
                display: true
            )
            bar.panel.orderFrontRegardless()
        }
        DisplayLayout.taskbarDisplays = wanted
        let places = buildPlaces()
        for bar in bars.values { bar.model.places = places }
        refresh()
    }

    private func makeBar(displayID: CGDirectDisplayID) -> Bar {
        let model = TaskbarModel(displayID: displayID)
        let panel = PanelFactory.make(level: PanelFactory.taskbarLevel, shadow: false)
        // Opaque: the Dock below must neither show through nor receive the mouse.
        panel.isOpaque = true
        panel.backgroundColor = TaskbarStyle.background
        let hosting = TaskbarHostingView(rootView: TaskbarView(model: model, controller: self))
        hosting.sizingOptions = [] // the panel's frame decides the size, not SwiftUI
        hosting.controller = self
        hosting.displayID = displayID
        hosting.itemFrames = { [weak model] in model?.itemFrames ?? [:] }
        panel.contentView = hosting
        return Bar(panel: panel, model: model)
    }

    // MARK: - Items

    private func refresh() {
        guard !refreshPending else { return }
        refreshPending = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.refreshPending = false
            self.rebuildItems()
        }
    }

    private func rebuildItems() {
        Perf.shared.measure("taskbar.rebuild", detail: "\(bars.count) bars") { rebuildItemsUnmeasured() }
    }

    private func rebuildItemsUnmeasured() {
        let screens = NSScreen.screens
        let windows = registry.currentSpaceWindows()
        let activeID = registry.activeWindowID()
        let running = registry.runningApps()
        let showEverything = bars.count == 1

        for (displayID, bar) in bars {
            let index = screens.firstIndex { DisplayLayout.displayID(of: $0) == displayID } ?? 0
            let local = showEverything ? windows : windows.filter {
                (DisplayLayout.screenIndex(for: $0.frame, in: screens) ?? 0) == index
            }
            bar.model.items = buildItems(windows: local, running: running, activeID: activeID)
        }
        popup.refreshIfVisible()
    }

    static func key(bundleID: String?, pid: pid_t) -> String {
        bundleID ?? "pid:\(pid)"
    }

    private func buildItems(windows: [WindowSnapshot], running: [NSRunningApplication], activeID: CGWindowID?) -> [TaskbarItem] {
        let settings = Settings.shared
        var order = settings.pinnedBundleIDs
        for app in running {
            let key = Self.key(bundleID: app.bundleIdentifier, pid: app.processIdentifier)
            if !order.contains(key) { order.append(key) }
        }
        for window in windows {
            let key = Self.key(bundleID: window.bundleID, pid: window.pid)
            if !order.contains(key) { order.append(key) }
        }

        var items: [TaskbarItem] = []
        for key in order {
            let appWindows = windows.filter { Self.key(bundleID: $0.bundleID, pid: $0.pid) == key }
            let pinned = settings.isPinned(key)
            guard pinned || !appWindows.isEmpty else { continue }

            let app = running.first { Self.key(bundleID: $0.bundleIdentifier, pid: $0.processIdentifier) == key }
            let bundleID = app?.bundleIdentifier ?? appWindows.first?.bundleID ?? (key.hasPrefix("pid:") ? nil : key)
            // A pinned app that is not installed any more is skipped.
            guard let name = app?.localizedName ?? appWindows.first?.appName ?? bundleID.flatMap({ self.displayName(forBundleID: $0) }) else {
                continue
            }
            let appIcon = app?.icon ?? appWindows.first?.icon ?? bundleID.flatMap { self.icon(forBundleID: $0) }
            let badge = badges[name]
            let hung = app.map { registry.unresponsive.contains($0.processIdentifier) } ?? false

            if settings.combineButtons || appWindows.isEmpty {
                items.append(TaskbarItem(
                    id: key, appKey: key, bundleID: bundleID, pid: app?.processIdentifier,
                    name: name, icon: appIcon, label: nil,
                    windowIDs: appWindows.map(\.id),
                    isRunning: app != nil,
                    isActive: activeID.map { active in appWindows.contains { $0.id == active } } ?? false,
                    badge: badge,
                    isNotResponding: hung
                ))
            } else {
                for (n, window) in appWindows.sorted(by: { $0.id < $1.id }).enumerated() {
                    items.append(TaskbarItem(
                        id: "\(key)#\(window.id)", appKey: key, bundleID: bundleID, pid: app?.processIdentifier,
                        name: name, icon: appIcon, label: window.title.isEmpty ? name : window.title,
                        windowIDs: [window.id],
                        isRunning: true,
                        isActive: activeID == window.id,
                        badge: n == 0 ? badge : nil,
                        isNotResponding: hung
                    ))
                }
            }
        }
        return items
    }

    private func displayName(forBundleID id: String) -> String? {
        if let cached = nameCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        nameCache[id] = name
        return name
    }

    private func icon(forBundleID id: String) -> NSImage? {
        if let cached = iconCache[id] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[id] = image
        return image
    }

    private func refreshBadges() {
        let fresh = Perf.shared.measure("dock.badges", quiet: true) { DockBadges.read() }
        if fresh != badges {
            badges = fresh
            refresh()
        }
    }

    // MARK: - Lookups used by the popup and the hosting view

    func item(_ itemID: String, on displayID: CGDirectDisplayID) -> TaskbarItem? {
        bars[displayID]?.model.items.first { $0.id == itemID }
    }

    /// The item's button in screen coordinates.
    func anchorRect(for itemID: String, on displayID: CGDirectDisplayID) -> NSRect? {
        guard let bar = bars[displayID], let local = bar.model.itemFrames[itemID] else { return nil }
        let panelFrame = bar.panel.frame
        return NSRect(
            x: panelFrame.minX + local.minX,
            y: panelFrame.maxY - local.maxY,
            width: local.width,
            height: local.height
        )
    }

    // MARK: - Actions

    func click(_ itemID: String, on displayID: CGDirectDisplayID) {
        calendar.close()
        popup.hideNow()
        guard let item = item(itemID, on: displayID) else { return }
        activate(item)
    }

    private func activate(_ item: TaskbarItem) {
        guard let first = item.windowIDs.first else {
            open(item)
            return
        }
        if item.isActive, let active = registry.activeWindowID(), item.windowIDs.contains(active) {
            registry.minimize(active)
        } else {
            registry.focus(first)
        }
    }

    func middleClick(_ itemID: String, on displayID: CGDirectDisplayID) {
        guard let item = item(itemID, on: displayID), let first = item.windowIDs.first else { return }
        registry.close(first)
    }

    func hover(_ itemID: String, on displayID: CGDirectDisplayID, inside: Bool) {
        if let model = bars[displayID]?.model {
            if inside {
                model.hoveredID = itemID
            } else if model.hoveredID == itemID {
                model.hoveredID = nil
            }
        }
        // Folders and the Trash have no window list.
        if itemID.hasPrefix("place:") {
            popup.itemExited()
            return
        }
        if inside {
            // Pointing at an app is when it matters whether it still responds.
            if let pid = item(itemID, on: displayID)?.pid { registry.probe(pid: pid) }
            popup.itemEntered(itemID, on: displayID)
        } else {
            popup.itemExited()
        }
    }

    /// Dragging a file over a button brings that app's window forward, as on Windows.
    func dragHover(_ itemID: String, on displayID: CGDirectDisplayID, targeted: Bool) {
        // SwiftUI may report "targeted" on every drag update; keep the first timer.
        if targeted, dragHoverItem == itemID, dragHoverTask != nil { return }
        dragHoverTask?.cancel()
        dragHoverTask = nil
        dragHoverItem = targeted ? itemID : nil
        guard targeted else { return }
        dragHoverTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, let self,
                  let first = self.item(itemID, on: displayID)?.windowIDs.first else { return }
            self.registry.focus(first)
        }
    }

    func toggleCalendar(on displayID: CGDirectDisplayID) {
        popup.hideNow()
        guard let bar = bars[displayID] else { return }
        let frame = bar.panel.frame
        calendar.toggle(anchor: NSRect(x: frame.maxX - 12, y: frame.minY, width: 1, height: frame.height))
    }

    // MARK: - Folders and Trash

    private func buildPlaces() -> [PlaceItem] {
        var places: [PlaceItem] = Settings.shared.pinnedFolderPaths.compactMap { path in
            guard FileManager.default.fileExists(atPath: path) else { return nil }
            return PlaceItem(
                id: "place:\(path)",
                name: FileManager.default.displayName(atPath: path),
                icon: NSWorkspace.shared.icon(forFile: path),
                url: URL(fileURLWithPath: path, isDirectory: true),
                isTrash: false
            )
        }
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        let trashIcon = NSImage(named: NSImage.trashEmptyName) ?? NSWorkspace.shared.icon(forFile: trash.path)
        places.append(PlaceItem(id: "place:trash", name: L("Trash"), icon: trashIcon, url: trash, isTrash: true))
        return places
    }

    func openPlace(_ place: PlaceItem) {
        calendar.close()
        popup.hideNow()
        NSWorkspace.shared.open(place.url)
    }

    /// Dropping files on the Trash button moves them to the Trash, as on Windows.
    func moveToTrash(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                do {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } catch {
                    Log.taskbar.error("Moving to Trash failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }

    func showDesktop() {
        calendar.close()
        popup.hideNow()
        ShowDesktop.toggle()
    }

    /// ⌃⌥1…9 — the n-th button on the taskbar of the display under the mouse.
    func activateItem(at index: Int) -> Bool {
        let screen = DisplayLayout.screen(containingMouse: NSEvent.mouseLocation)
        let displayID = screen.map { DisplayLayout.displayID(of: $0) }
        guard let bar = displayID.flatMap({ bars[$0] }) ?? bars.values.first,
              bar.model.items.indices.contains(index) else { return false }
        activate(bar.model.items[index])
        return true
    }

    private func open(_ item: TaskbarItem) {
        let url: URL?
        if let pid = item.pid, let app = NSRunningApplication(processIdentifier: pid) {
            url = app.bundleURL
        } else {
            url = item.bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        }
        guard let url else { return }
        // For a running app this sends "reopen", which makes most apps open a window.
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func contextMenu(for itemID: String, on displayID: CGDirectDisplayID) -> NSMenu? {
        guard let item = item(itemID, on: displayID) else { return nil }
        popup.hideNow()
        calendar.close()
        let menu = NSMenu()
        let app = item.pid.flatMap { NSRunningApplication(processIdentifier: $0) }

        if item.windowIDs.count > 1 {
            for id in item.windowIDs {
                guard let window = registry.window(id) else { continue }
                let title = window.title.isEmpty ? item.name : window.title
                menu.addItem(ClosureMenuItem(title) { [weak self] in self?.registry.focus(id) })
            }
            menu.addItem(.separator())
        }

        if let app {
            menu.addItem(ClosureMenuItem(L("New Window")) { NewWindow.open(in: app) })
        } else {
            menu.addItem(ClosureMenuItem(String(format: L("Open %@"), item.name)) { [weak self] in self?.open(item) })
        }

        if let bundleID = item.bundleID {
            let title = Settings.shared.isPinned(bundleID) ? L("Unpin from taskbar") : L("Pin to taskbar")
            menu.addItem(ClosureMenuItem(title) { Settings.shared.togglePin(bundleID) })
        }

        if !item.windowIDs.isEmpty || app != nil {
            menu.addItem(.separator())
        }
        if !item.windowIDs.isEmpty {
            let title = item.windowIDs.count > 1 ? L("Close all windows") : L("Close window")
            let ids = item.windowIDs
            menu.addItem(ClosureMenuItem(title) { [weak self] in
                for id in ids { self?.registry.close(id) }
            })
        }
        if let app {
            menu.addItem(ClosureMenuItem(String(format: L("Quit %@"), item.name)) { _ = app.terminate() })
        }
        return menu
    }
}
