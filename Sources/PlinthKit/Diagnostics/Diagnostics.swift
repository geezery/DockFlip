import AppKit
import OSLog

/// Loggers by area. Messages go to the unified log (Console.app, `log show`) and
/// into the exported debug log. Window titles are never logged — app names only.
enum Log {
    static let subsystem = Bundle.main.bundleIdentifier ?? "io.github.plinth.Plinth"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let registry = Logger(subsystem: subsystem, category: "registry")
    static let keys = Logger(subsystem: subsystem, category: "keys")
    static let switcher = Logger(subsystem: subsystem, category: "switcher")
    static let taskbar = Logger(subsystem: subsystem, category: "taskbar")
    static let snap = Logger(subsystem: subsystem, category: "snap")
    static let previews = Logger(subsystem: subsystem, category: "previews")
    static let perf = Logger(subsystem: subsystem, category: "perf")
}

/// In-memory timing statistics for the hot paths. Always on (it is a clock read
/// and a dictionary update); detailed per-call logging only when debug logging is on.
@MainActor
final class Perf {
    static let shared = Perf()

    struct Stat {
        var count = 0
        var total: Double = 0
        var max: Double = 0
        var maxDetail = ""
        var slow = 0
    }

    /// Calls slower than this are always logged, and counted as slow.
    static let slowThresholdMs: Double = 50

    private(set) var stats: [String: Stat] = [:]
    let launchDate = Date()

    var verbose: Bool { Settings.shared.debugLogging }

    @discardableResult
    /// `quiet`: for calls that happen on every key press or window move — counted,
    /// but logged one by one only when slow.
    func measure<T>(_ name: String, detail: @autoclosure () -> String = "", quiet: Bool = false, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            record(name, ms: ms, detail: detail(), quiet: quiet)
        }
        return try body()
    }

    /// Milliseconds since `start` (from `Perf.now()`), for async work.
    static func now() -> UInt64 {
        DispatchTime.now().uptimeNanoseconds
    }

    func record(_ name: String, since start: UInt64, detail: String = "") {
        record(name, ms: Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000, detail: detail)
    }

    func record(_ name: String, ms: Double, detail: String = "", quiet: Bool = false) {
        var stat = stats[name] ?? Stat()
        stat.count += 1
        stat.total += ms
        if ms > stat.max {
            stat.max = ms
            stat.maxDetail = detail
        }
        if ms >= Self.slowThresholdMs {
            stat.slow += 1
            Log.perf.notice("SLOW \(name, privacy: .public) \(ms, format: .fixed(precision: 1), privacy: .public) ms \(detail, privacy: .public)")
        } else if verbose && !quiet {
            Log.perf.notice("\(name, privacy: .public) \(ms, format: .fixed(precision: 2), privacy: .public) ms \(detail, privacy: .public)")
        }
        stats[name] = stat
    }

    func reset() {
        stats = [:]
    }
}

/// Builds the debug log file the user can send for analysis.
@MainActor
enum Diagnostics {
    /// Extra lines for the report (tracked apps and windows), supplied by AppDelegate.
    static var stateProvider: (() -> [String])?

    static func exportLog() {
        var lines: [String] = []
        let info = ProcessInfo.processInfo
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let uptime = Date().timeIntervalSince(Perf.shared.launchDate)

        lines.append("Plinth debug log")
        lines.append("Created: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Plinth \(version) (\(build)), running \(Int(uptime / 60)) min")
        lines.append("macOS \(info.operatingSystemVersionString), model \(hardwareModel()), \(info.processorCount) cores, \(info.physicalMemory / 1_073_741_824) GB")
        lines.append("Memory (resident): \(residentMemoryMB()) MB")
        lines.append("")

        lines.append("== Displays ==")
        for (index, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            let v = screen.visibleFrame
            lines.append("#\(index) \(screen.localizedName): frame \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)), visible \(Int(v.minY - f.minY)) pt from bottom, scale \(screen.backingScaleFactor)")
        }
        lines.append("")

        lines.append("== Settings ==")
        let s = Settings.shared
        lines.append("previews=\(s.previewsEnabled) screenRecording=\(CGPreflightScreenCaptureAccess()) combine=\(s.combineButtons) allDisplays=\(s.taskbarOnAllDisplays) shortcuts=\(s.shortcutsEnabled) accessibility=\(Permissions.isAccessibilityTrusted)")
        lines.append("dockFitted=\(SystemTweaks.isDockFitted) nativeEdgeTiling=\(SystemTweaks.isNativeEdgeTilingOn) pinned=\(s.pinnedBundleIDs.count)")
        lines.append("")

        if let state = stateProvider?() {
            lines.append("== State ==")
            lines.append(contentsOf: state)
            lines.append("")
        }

        lines.append("== Timings (ms) ==")
        lines.append(pad("name", 28) + pad("count", 8) + pad("avg", 9) + pad("max", 9) + pad("slow", 6) + "slowest")
        for (name, stat) in Perf.shared.stats.sorted(by: { $0.value.total > $1.value.total }) {
            let avg = stat.count > 0 ? stat.total / Double(stat.count) : 0
            lines.append(pad(name, 28) + pad("\(stat.count)", 8) + pad(String(format: "%.2f", avg), 9)
                         + pad(String(format: "%.1f", stat.max), 9) + pad("\(stat.slow)", 6) + stat.maxDetail)
        }
        lines.append("")

        lines.append("== Log since launch ==")
        lines.append(contentsOf: logEntries())

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        let url = desktop.appendingPathComponent("Plinth-debug-\(formatter.string(from: Date())).txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            Log.app.notice("Debug log written")
        } catch {
            Log.app.error("Could not write the debug log: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    /// This process's own unified-log entries since launch. Reading one's own
    /// entries needs no special permission.
    private static func logEntries() -> [String] {
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(date: Perf.shared.launchDate)
            let entries = try store.getEntries(at: position)
            let time = DateFormatter()
            time.dateFormat = "HH:mm:ss.SSS"
            var lines: [String] = []
            for entry in entries {
                guard let log = entry as? OSLogEntryLog, log.subsystem == Log.subsystem else { continue }
                let level: String
                switch log.level {
                case .error, .fault: level = "ERROR"
                case .notice: level = "note "
                case .info: level = "info "
                case .debug: level = "debug"
                default: level = "     "
                }
                lines.append("\(time.string(from: log.date)) \(level) [\(log.category)] \(log.composedMessage)")
            }
            return lines.suffix(5000).map { $0 }
        } catch {
            return ["(could not read the log: \(error.localizedDescription))"]
        }
    }

    private static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text + " " : text + String(repeating: " ", count: width - text.count)
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "?" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }

    private static func residentMemoryMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size / 1_048_576) : -1
    }
}
