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

@MainActor
final class CleanupModel: ObservableObject {
    @Published var windows: [CleanupRow] = []
    @Published var apps: [CleanupRow] = []
    @Published var selected = Set<CleanupRow.Target>()

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

    init(registry: WindowRegistry, usage: UsageTracker) {
        self.registry = registry
        self.usage = usage
    }

    private var keep: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.keepKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue).sorted(), forKey: Self.keepKey) }
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
                _ = NSRunningApplication(processIdentifier: pid)?.terminate()
            }
        }
        Log.app.notice("Clean up: closed \(targets.count, privacy: .public) items")
        // Apps may ask to save first; look again once they had a moment.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.reload()
        }
    }

    func keepAlways(_ row: CleanupRow) {
        guard let bundleID = row.bundleID else { return }
        var set = keep
        set.insert(bundleID)
        keep = set
        reload()
    }

    func toggle(_ target: CleanupRow.Target) {
        if model.selected.contains(target) {
            model.selected.remove(target)
        } else {
            model.selected.insert(target)
        }
    }

    // MARK: - Data

    func reload() {
        let (windowRows, appRows) = candidates()
        model.windows = windowRows
        model.apps = appRows
        model.selected = Set(windowRows.map(\.id) + appRows.map(\.id))
    }

    private func candidates() -> ([CleanupRow], [CleanupRow]) {
        let now = Date()
        let keep = self.keep
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

// MARK: - View

struct CleanupView: View {
    @ObservedObject var model: CleanupModel
    let controller: CleanupController

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Clean Up").font(.system(size: 22, weight: .bold))
                Text("Windows you have not used for three days and apps left running without windows. Nothing is closed without you, and apps still ask to save your work.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            if model.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.system(size: 32)).foregroundStyle(Color.accentColor)
                    Text("Nothing to clean up").font(.system(size: 15, weight: .semibold))
                    Text("Everything open has been used recently.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !model.windows.isEmpty {
                        Section("Unused windows") {
                            ForEach(model.windows) { row in
                                CleanupRowView(row: row, model: model, controller: controller)
                            }
                        }
                    }
                    if !model.apps.isEmpty {
                        Section("Apps without windows") {
                            ForEach(model.apps) { row in
                                CleanupRowView(row: row, model: model, controller: controller)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Text(String(format: L("%ld selected"), model.selected.count))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close Selected") { controller.closeSelected() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.selected.isEmpty)
            }
            .padding(16)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}

struct CleanupRowView: View {
    let row: CleanupRow
    @ObservedObject var model: CleanupModel
    let controller: CleanupController

    private var detail: String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        var parts = [String(format: L("used %@"), relative.localizedString(for: row.lastUsed, relativeTo: Date()))]
        if let bytes = row.memoryBytes {
            parts.append(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory))
        }
        if case .window = row.id { parts.insert(row.appName, at: 0) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { MainActor.assumeIsolated { model.selected.contains(row.id) } },
                set: { _ in MainActor.assumeIsolated { controller.toggle(row.id) } }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            AppIconView(icon: row.icon, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.title).font(.system(size: 13)).lineLimit(1)
                Text(verbatim: detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if row.bundleID != nil {
                Button("Keep") { controller.keepAlways(row) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12))
                    .help(Text("Never suggest this app again"))
            }
        }
        .padding(.vertical, 2)
    }
}
