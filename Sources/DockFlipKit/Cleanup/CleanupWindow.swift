import AppKit
import Darwin
import SwiftUI

struct CleanupRow: Identifiable {
    enum Target: Hashable {
        case window(CGWindowID)
        case app(pid_t)
    }

    let id: Target
    let title: String
    let appName: String
    let bundleID: String?
    let icon: NSImage?
    let lastUsed: Date
    let memoryBytes: Int64?
}

/// An app the user asked Clean Up never to suggest, for the "Kept Apps" list.
struct KeptAppRow: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
}

@MainActor
final class CleanupModel: ObservableObject {
    @Published var windows: [CleanupRow] = []
    @Published var apps: [CleanupRow] = []
    @Published var selected = Set<CleanupRow.Target>()
    @Published var kept: [KeptAppRow] = []
    @Published var showsKept = false

    var isEmpty: Bool { windows.isEmpty && apps.isEmpty }
}

/// "Clean up": windows and apps left unused for days, closed only when the user says so.
@MainActor
final class CleanupController {
    private static let keepKey = "cleanup.keepBundleIDs"

    private let registry: WindowRegistry
    private let usage: UsageTracker
    private let model = CleanupModel()
    private var window: NSWindow?
    private var refresh = CleanupRefresh()
    private var tokens: [NSObjectProtocol] = []

    init(registry: WindowRegistry, usage: UsageTracker) {
        self.registry = registry
        self.usage = usage
        // Windows closed elsewhere leave the registry; apps quit from the Dock may
        // have no tracked windows, so their end comes from the workspace instead.
        registry.addObserver { [weak self] in self?.listChanged() }
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.listChanged() }
        })
    }

    /// Something may have gone while Clean Up is open: look again after a short
    /// one-shot wait, so a burst of changes makes one reload.
    private func listChanged() {
        guard refresh.changed(isVisible: window?.isVisible == true) else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: CleanupRefresh.delay)
            guard let self, self.refresh.fire(isVisible: self.window?.isVisible == true) else { return }
            self.reload()
        }
    }

    private var kept: KeptApps {
        get { KeptApps(UserDefaults.standard.stringArray(forKey: Self.keepKey) ?? []) }
        set { UserDefaults.standard.set(newValue.bundleIDs, forKey: Self.keepKey) }
    }

    /// Number of suggestions, for the menu bar menu.
    func candidateCount() -> Int {
        let (windows, apps) = candidates()
        return windows.count + apps.count
    }

    func show() {
        reload()
        if window == nil {
            let view = CleanupView(model: model, controller: self)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable, .resizable]
            window.title = L("Clean Up")
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 560, height: 520))
            window.center()
            // Coming back to Clean Up from elsewhere: catch what changed meanwhile.
            tokens.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.listChanged() }
            })
            self.window = window
        }
        if let window { WindowPresenter.bringToFront(window) }
    }

    // MARK: - Actions

    func closeSelected() {
        let targets = model.selected
        for target in targets {
            switch target {
            case .window(let id):
                registry.close(id)
            case .app(let pid):
                guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
                followUpQuit(of: app, wasAsked: app.terminate())
            }
        }
        Log.app.notice("Clean up: closed \(targets.count, privacy: .public) items")
        // Apps may ask to save first; look again once they had a moment.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.reload()
        }
    }

    /// One-shot look, never a repeating timer: an app that asks to review changes
    /// is still running a second later, and its question is shown where it can be seen.
    private func followUpQuit(of app: NSRunningApplication, wasAsked: Bool) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let check = QuitFollowUp.Check(
                wasAsked: wasAsked,
                isTerminated: app.isTerminated,
                isHidden: app.isHidden,
                isActive: app.isActive
            )
            guard QuitFollowUp.after(check) == .bringForward else { return }
            let name = app.localizedName ?? "?"
            Log.app.notice("Clean up: bringing forward an app that asks first: \(name, privacy: .public)")
            if app.isHidden { app.unhide() }
            _ = app.activate(options: [])
        }
    }

    /// "Keep": not now. Only this window (or app) counts as used now and comes back
    /// after it sits unused as long again; the app's other windows stay suggested.
    func keepForNow(_ row: CleanupRow) {
        switch row.id {
        case .window(let id):
            usage.markUsed(window: id)
        case .app(let pid):
            // An app that quit meanwhile has nothing to mark; the reload drops its row.
            if let app = NSRunningApplication(processIdentifier: pid) { usage.markUsed(app: app) }
        }
        reload()
    }

    /// Every window of the app, now and later, until removed from "Kept Apps".
    func neverSuggest(_ row: CleanupRow) {
        guard let bundleID = row.bundleID else { return }
        var kept = self.kept
        kept.add(bundleID)
        self.kept = kept
        reload()
    }

    func suggestAgain(_ bundleID: String) {
        var kept = self.kept
        kept.remove(bundleID)
        self.kept = kept
        // "Suggest again" is not "close": its windows come back listed but unticked.
        reload(comeBackUntickedBundleID: bundleID)
    }

    func toggle(_ target: CleanupRow.Target) {
        if model.selected.contains(target) {
            model.selected.remove(target)
        } else {
            model.selected.insert(target)
        }
    }

    // MARK: - Data

    /// `comeBackUntickedBundleID`: the app just removed from "Kept Apps", whose rows
    /// are listed again but must not come in ticked for the next Close Selected.
    func reload(comeBackUntickedBundleID: String? = nil) {
        let (windowRows, appRows) = candidates()
        let previouslyListed = Set(model.windows.map(\.id) + model.apps.map(\.id))
        let comeBackUnticked = Set(
            (windowRows + appRows)
                .filter { comeBackUntickedBundleID != nil && $0.bundleID == comeBackUntickedBundleID }
                .map(\.id)
        )
        model.windows = windowRows
        model.apps = appRows
        model.selected = CleanupSelection.afterReload(
            listed: windowRows.map(\.id) + appRows.map(\.id),
            previouslyListed: previouslyListed,
            selected: model.selected,
            comeBackUnticked: comeBackUnticked
        )
        model.kept = keptRows()
        if model.kept.isEmpty { model.showsKept = false }
    }

    /// Names and icons from the installed app; an app no longer installed shows its bundle id.
    private func keptRows() -> [KeptAppRow] {
        kept.bundleIDs.map { bundleID in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return KeptAppRow(id: bundleID, name: bundleID, icon: nil)
            }
            return KeptAppRow(
                id: bundleID,
                name: FileManager.default.displayName(atPath: url.path),
                icon: NSWorkspace.shared.icon(forFile: url.path)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func candidates() -> ([CleanupRow], [CleanupRow]) {
        let now = Date()
        let keep = self.kept.set
        let snapshots = registry.currentSpaceWindows()
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })

        let windowInputs = snapshots.map {
            CleanupEngine.WindowInput(id: $0.id, bundleID: $0.bundleID, lastUsed: usage.lastUsed(window: $0.id))
        }
        let windowRows: [CleanupRow] = CleanupEngine.idleWindows(windowInputs, now: now, keep: keep).compactMap { id in
            guard let window = byID[id] else { return nil }
            return CleanupRow(
                id: .window(id),
                title: window.title.isEmpty ? window.appName : window.title,
                appName: window.appName,
                bundleID: window.bundleID,
                icon: window.icon,
                lastUsed: usage.lastUsed(window: id),
                memoryBytes: nil
            )
        }

        let withWindows = Set(WindowServer.inventory(visibleOnly: true).keys)
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let own = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated
        }
        let appInputs = running.map {
            CleanupEngine.AppInput(
                pid: $0.processIdentifier,
                bundleID: $0.bundleIdentifier,
                hasWindows: withWindows.contains($0.processIdentifier),
                isFrontmost: $0.processIdentifier == frontmost,
                lastUsed: usage.lastUsed(app: $0)
            )
        }
        let byPID = Dictionary(uniqueKeysWithValues: running.map { ($0.processIdentifier, $0) })
        let appRows: [CleanupRow] = CleanupEngine.idleApps(appInputs, now: now, keep: keep).compactMap { pid in
            guard let app = byPID[pid] else { return nil }
            let name = app.localizedName ?? app.bundleIdentifier ?? "?"
            return CleanupRow(
                id: .app(pid),
                title: name,
                appName: name,
                bundleID: app.bundleIdentifier,
                icon: app.icon,
                lastUsed: usage.lastUsed(app: app),
                memoryBytes: ProcessInfoReader.memoryFootprint(of: pid)
            )
        }
        return (windowRows, appRows)
    }
}

/// Memory use of other processes, without any extra permission.
enum ProcessInfoReader {
    static func memoryFootprint(of pid: pid_t) -> Int64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? Int64(info.ri_phys_footprint) : nil
    }
}
