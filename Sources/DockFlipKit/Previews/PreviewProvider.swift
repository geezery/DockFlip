import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Opt-in window thumbnails.
///
/// Safety rules (see SCOPE.md), enforced here and nowhere else:
/// - Only when the user turned previews on and macOS granted Screen Recording.
/// - One window at a time, captured at thumbnail size: full-resolution pixels
///   never enter DockFlip's memory.
/// - Only on demand (Dock icon hover, ⌘Tab). The last image of a window is
///   kept in memory for up to two minutes (at most 24 images), so a list opens
///   with pictures at once and windows that cannot be captured right now
///   (minimized, on another desktop) still show how they looked. Never written
///   to disk; all dropped when the screen locks or the Mac sleeps.
/// - Never while a password field is focused anywhere (secure keyboard entry),
///   and never for password managers, Keychain Access or System Settings.
@MainActor
final class PreviewProvider {
    static let shared = PreviewProvider()

    static let maxPixelWidth: CGFloat = 760
    /// An image this fresh is shown without capturing again.
    private static let freshFor: TimeInterval = 2
    /// Images are kept this long, and at most `maxCached` of them.
    private static let keptFor: TimeInterval = 120
    private static let maxCached = 24

    private static let neverCapture: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.apple.systempreferences",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass"
    ]

    private var cache: [CGWindowID: (image: NSImage, time: Date)] = [:]
    /// The window list from ScreenCaptureKit, reused for a moment so one ⌘Tab does not ask for it 20 times.
    private var content: (value: SCShareableContent, time: Date)?
    /// The window list being fetched; captures that start together share it.
    private var contentTask: Task<SCShareableContent, Error>?

    private func shareableContent() async throws -> SCShareableContent {
        if let content, Date().timeIntervalSince(content.time) < 1 { return content.value }
        if let contentTask { return try await contentTask.value }
        let task = Task { try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        contentTask = task
        defer { contentTask = nil }
        let fresh = try await task.value
        content = (fresh, Date())
        return fresh
    }
    private var tokens: [NSObjectProtocol] = []

    private init() {
        let clear: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                self?.cache.removeAll()
                self?.content = nil
            }
        }
        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: clear))
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: clear))
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: clear))
    }

    /// True when previews may be shown at all.
    var isAvailable: Bool {
        Settings.shared.previewsEnabled && CGPreflightScreenCaptureAccess()
    }

    /// Asks macOS for Screen Recording. macOS may require DockFlip to restart before it applies.
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// The last image of a window still in memory, without capturing.
    func cachedThumbnail(for id: CGWindowID) -> NSImage? {
        guard isAvailable else { return nil }
        prune()
        return cache[id]?.image
    }

    private func prune() {
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.time) < Self.keptFor }
        if cache.count > Self.maxCached {
            let oldest = cache.sorted { $0.value.time < $1.value.time }.prefix(cache.count - Self.maxCached)
            for (id, _) in oldest { cache[id] = nil }
        }
    }

    /// A fresh image of the window — or, when it cannot be captured right now
    /// (minimized, hidden, on another desktop), the last one in memory.
    func thumbnail(for window: WindowSnapshot) async -> NSImage? {
        guard isAvailable else { return nil }
        if let bundleID = window.bundleID, Self.neverCapture.contains(bundleID) { return nil }
        guard !IsSecureEventInputEnabled() else { return nil }

        prune()
        let cached = cache[window.id]
        if let cached, Date().timeIntervalSince(cached.time) < Self.freshFor { return cached.image }
        guard !window.isMinimized, !window.isAppHidden, !window.isOnOtherSpace else { return cached?.image }

        let start = Perf.now()
        defer { Perf.shared.record("previews.capture", since: start, detail: window.appName) }
        do {
            let content = try await shareableContent()
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }),
                  scWindow.frame.width > 0, scWindow.frame.height > 0 else { return cached?.image }

            let scale = min(1, Self.maxPixelWidth / scWindow.frame.width)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(scWindow.frame.width * scale))
            configuration.height = max(1, Int(scWindow.frame.height * scale))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

            // Re-check: a password field may have gained focus while capturing.
            guard !IsSecureEventInputEnabled() else { return nil }
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            cache[window.id] = (image, Date())
            return image
        } catch {
            return cached?.image
        }
    }
}
