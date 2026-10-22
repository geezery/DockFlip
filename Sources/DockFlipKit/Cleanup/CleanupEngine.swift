import CoreGraphics
import Foundation

/// Pure rules for the cleaner, unit-tested. Nothing here closes anything.
public enum CleanupEngine {
    /// A window nobody has focused for this long is suggested for closing.
    public static let windowIdle: TimeInterval = 3 * 24 * 3600
    /// An app with no windows left, unused for this long, is suggested for quitting.
    public static let windowlessAppIdle: TimeInterval = 24 * 3600
    /// Never suggested, whatever their age.
    public static let alwaysKept: Set<String> = ["com.apple.finder"]

    public struct WindowInput {
        public let id: CGWindowID
        public let bundleID: String?
        public let lastUsed: Date
        public init(id: CGWindowID, bundleID: String?, lastUsed: Date) {
            self.id = id
            self.bundleID = bundleID
            self.lastUsed = lastUsed
        }
    }

    public struct AppInput {
        public let pid: pid_t
        public let bundleID: String?
        public let hasWindows: Bool
        public let isFrontmost: Bool
        public let lastUsed: Date
        public init(pid: pid_t, bundleID: String?, hasWindows: Bool, isFrontmost: Bool, lastUsed: Date) {
            self.pid = pid
            self.bundleID = bundleID
            self.hasWindows = hasWindows
            self.isFrontmost = isFrontmost
            self.lastUsed = lastUsed
        }
    }

    /// Idle windows, the longest unused first.
    public static func idleWindows(_ windows: [WindowInput], now: Date, keep: Set<String>) -> [CGWindowID] {
        windows
            .filter { now.timeIntervalSince($0.lastUsed) >= windowIdle && !isKept($0.bundleID, keep) }
            .sorted { $0.lastUsed < $1.lastUsed }
            .map(\.id)
    }

    /// Running apps without any window, the longest unused first.
    public static func idleApps(_ apps: [AppInput], now: Date, keep: Set<String>) -> [pid_t] {
        apps
            .filter { !$0.hasWindows && !$0.isFrontmost
                && now.timeIntervalSince($0.lastUsed) >= windowlessAppIdle
                && !isKept($0.bundleID, keep) }
            .sorted { $0.lastUsed < $1.lastUsed }
            .map(\.pid)
    }

    private static func isKept(_ bundleID: String?, _ keep: Set<String>) -> Bool {
        guard let bundleID else { return false }
        return alwaysKept.contains(bundleID) || keep.contains(bundleID)
    }
}
