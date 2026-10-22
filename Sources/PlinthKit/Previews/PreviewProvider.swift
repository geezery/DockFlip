import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Opt-in window thumbnails.
///
/// Safety rules (see SCOPE.md), enforced here and nowhere else:
/// - Only when the user turned previews on and macOS granted Screen Recording.
/// - One window at a time, captured at thumbnail size: full-resolution pixels
///   never enter Plinth's memory.
/// - Only on demand (taskbar hover, ⌘Tab); kept in memory for a few seconds,
///   never written to disk, dropped when the screen locks or the Mac sleeps.
/// - Never while a password field is focused anywhere (secure keyboard entry),
///   and never for password managers, Keychain Access or System Settings.
@MainActor
final class PreviewProvider {
    static let shared = PreviewProvider()

    static let maxPixelWidth: CGFloat = 760
    private static let cacheLifetime: TimeInterval = 3

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

    private func shareableContent() async throws -> SCShareableContent {
        if let content, Date().timeIntervalSince(content.time) < 1 { return content.value }
        let fresh = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
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

    /// Asks macOS for Screen Recording. macOS may require Plinth to restart before it applies.
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    func thumbnail(for window: WindowSnapshot) async -> NSImage? {
        guard isAvailable, !window.isMinimized, !window.isAppHidden else { return nil }
        if let bundleID = window.bundleID, Self.neverCapture.contains(bundleID) { return nil }
        guard !IsSecureEventInputEnabled() else { return nil }

        // Expired thumbnails are dropped, not just skipped.
        let now = Date()
        cache = cache.filter { now.timeIntervalSince($0.value.time) < Self.cacheLifetime }
        if let cached = cache[window.id] { return cached.image }

        let start = Perf.now()
        defer { Perf.shared.record("previews.capture", since: start, detail: window.appName) }
        do {
            let content = try await shareableContent()
            guard let scWindow = content.windows.first(where: { $0.windowID == window.id }),
                  scWindow.frame.width > 0, scWindow.frame.height > 0 else { return nil }

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
            return nil
        }
    }
}
