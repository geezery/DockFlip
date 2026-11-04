import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Opt-in window thumbnails.
///
/// Safety rules (see SCOPE.md), enforced here and nowhere else:
/// - Only when the user turned previews on and macOS granted Screen Recording.
/// - One window per capture, at thumbnail size: full-resolution pixels never
///   enter DockFlip's memory.
/// - Only on demand: when the mouse rests on a Dock icon, when ⌘Tab is pressed,
///   for Snap Assist. Then only windows whose picture is out of date
///   (`PreviewFreshness`): usually just the window one worked in last.
/// - The last picture of each open window is kept in memory, packed as HEIC
///   (`PictureCodec`), at most `maxKept`, so ⌘Tab and the Dock share them and open
///   with pictures at once, and windows that cannot be captured right now
///   (minimized, on another desktop) still show how they looked. Never written
///   to disk; dropped when the window closes, the screen locks or the Mac sleeps.
/// - Never while a password field is focused anywhere (secure keyboard entry),
///   and never for password managers, Keychain Access, System Settings or
///   browsers' private windows (`NeverPictured`).
@MainActor
final class PreviewProvider {
    static let shared = PreviewProvider()

    /// The widest picture taken, in pixels: ⌘Tab's front card and the Dock's peek pane.
    nonisolated static let maxPixelWidth: CGFloat = 760
    /// The Dock list's cards are about 190 points wide: twice that on a Retina screen.
    nonisolated static let cardPixelSize = 400
    /// Pictures kept, the least recently used dropped first.
    nonisolated static let maxKept = 64
    /// A picture this fresh is used without capturing again, even of the active
    /// window, so the Dock list and a ⌘Tab right after it do not both capture it.
    private static let freshFor: TimeInterval = 1
    /// A failed capture is tried once more after this (ScreenCaptureKit is often
    /// just busy for a moment).
    private static let retryAfter: Duration = .milliseconds(250)

    /// A picture kept in memory: HEIC, or the bitmap when packing failed.
    private struct Kept: @unchecked Sendable {
        let heic: Data?
        let bitmap: CGImage?
        var lastUsed: Date
        var takenAt: Date
        var bytes: Int { heic?.count ?? (bitmap.map { $0.bytesPerRow * $0.height } ?? 0) }
    }

    private var kept: [CGWindowID: Kept] = [:]
    private var freshness = PreviewFreshness<CGWindowID>()
    private var queue = CaptureQueue<CGWindowID>()
    /// Captures under way, shared by everyone who asks for the same window. They
    /// finish even when the list or ⌘Tab that asked has closed: the picture is kept.
    private var inFlight: [CGWindowID: Task<Kept?, Never>] = [:]
    private var waitingForTurn: [CGWindowID: CheckedContinuation<Void, Never>] = [:]
    /// Bumped when everything is dropped (screen lock, sleep): a capture that
    /// started before keeps nothing.
    private var generation = 0
    private var activeWindow: CGWindowID?
    private var stats = (captured: 0, reused: 0, failed: 0, retried: 0, packFailed: 0)

    /// The window list from ScreenCaptureKit, reused for a moment so one ⌘Tab does not ask for it many times.
    private var content: (value: SCShareableContent, time: Date)?
    /// The window list being fetched; captures that start together share it.
    private var contentTask: Task<ContentBox, Error>?

    /// Carries values out of tasks.
    private final class ContentBox: @unchecked Sendable {
        let value: SCShareableContent
        init(_ value: SCShareableContent) { self.value = value }
    }
    private final class ImageBox: @unchecked Sendable {
        let image: CGImage
        init(_ image: CGImage) { self.image = image }
    }

    private var tokens: [NSObjectProtocol] = []

    private init() {
        let clear: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.dropAll() }
        }
        tokens.append(DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: clear))
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: clear))
        tokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main, using: clear))
    }

    private func dropAll() {
        generation += 1
        kept.removeAll()
        freshness.forgetAll()
        content = nil
    }

    /// Follows the windows: which one is active (a window worked in needs a new
    /// picture) and which closed (their pictures go). Called once, by `Services`.
    func follow(_ registry: WindowRegistry) {
        registry.addObserver { [weak self, weak registry] in
            guard let self, let registry else { return }
            self.windowsChanged(active: registry.activeWindowID()) { registry.window($0) != nil }
        }
    }

    private func windowsChanged(active: CGWindowID?, exists: (CGWindowID) -> Bool) {
        if active != activeWindow {
            // Both were in use until now: the one left and the one coming forward.
            if let activeWindow { freshness.used(activeWindow) }
            if let active { freshness.used(active) }
            activeWindow = active
        }
        let closed = kept.keys.filter { !exists($0) }
        for id in closed {
            kept[id] = nil
            freshness.forget(id)
        }
    }

    /// True when previews may be shown at all.
    var isAvailable: Bool {
        ThumbnailAccess(enabled: Settings.shared.previewsEnabled,
                        screenRecordingAllowed: CGPreflightScreenCaptureAccess()) == .on
    }

    /// Windows never pictured, whatever the settings: apps that show passwords
    /// and secrets, and browsers' private windows (`NeverPictured`).
    static func neverPictured(_ window: WindowSnapshot) -> Bool {
        NeverPictured.contains(bundleID: window.bundleID, title: window.title)
    }

    /// Asks macOS for Screen Recording. macOS may require DockFlip to restart before it applies.
    static func requestPermission() {
        _ = CGRequestScreenCaptureAccess()
    }

    /// Opens System Settings at Privacy & Security → Screen & System Audio Recording.
    static func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Fetches ScreenCaptureKit's window list ahead of a capture (the mouse
    /// reached a Dock icon): it is the slow part of the first picture.
    func prefetchWindowList() {
        guard isAvailable, contentTask == nil else { return }
        Task { @MainActor [weak self] in _ = try? await self?.shareableContent(fresh: false) }
    }

    /// Shows `window`'s picture: first the one memory keeps, unpacked to
    /// `maxPixelSize` (its longer side), then a fresh one when the kept one is out
    /// of date or missing. `deliver` runs on the main actor, at most twice.
    ///
    /// Cancelling the calling task stops deliveries, not a capture under way: its
    /// picture is kept for the next list or ⌘Tab. `urgent` puts the capture ahead
    /// of the others waiting (the hovered window, the card stepped to).
    func loadPicture(of window: WindowSnapshot, maxPixelSize: Int = Int(PreviewProvider.maxPixelWidth),
                     urgent: Bool = false, deliver: (NSImage) -> Void) async {
        guard isAvailable else { return }
        // Drop any picture taken before the window became private (a title change).
        if Self.neverPictured(window) {
            kept[window.id] = nil
            freshness.forget(window.id)
            return
        }
        let id = window.id
        if var picture = kept[id] {
            picture.lastUsed = Date()
            kept[id] = picture
            if let image = await unpack(picture, maxPixelSize: maxPixelSize), !Task.isCancelled {
                deliver(image)
            }
        }
        guard !Task.isCancelled, needsCapture(window) else {
            stats.reused += 1
            return
        }
        guard let fresh = await capture(window, urgent: urgent).value, !Task.isCancelled,
              let image = await unpack(fresh, maxPixelSize: maxPixelSize), !Task.isCancelled else { return }
        deliver(image)
    }

    private func needsCapture(_ window: WindowSnapshot) -> Bool {
        // Cannot be captured now: the kept picture is the best there is.
        guard !window.isMinimized, !window.isAppHidden, !window.isOnOtherSpace else { return false }
        guard !IsSecureEventInputEnabled() else { return false }
        if let picture = kept[window.id], Date().timeIntervalSince(picture.takenAt) < Self.freshFor { return false }
        return freshness.needsPicture(window.id, now: Self.signature(of: window), isActive: window.id == activeWindow)
    }

    private static func signature(of window: WindowSnapshot) -> PreviewFreshness<CGWindowID>.Signature {
        .init(title: window.title, size: window.frame.size)
    }

    /// The capture of `window`, shared with whoever asked for it already.
    private func capture(_ window: WindowSnapshot, urgent: Bool) -> Task<Kept?, Never> {
        if let running = inFlight[window.id] {
            if urgent { queue.promote(window.id) }
            return running
        }
        let task = Task { @MainActor [weak self] () -> Kept? in
            guard let self else { return nil }
            await self.waitForTurn(window.id, urgent: urgent)
            defer { self.finishTurn(window.id) }
            return await self.captureAndKeep(window)
        }
        inFlight[window.id] = task
        return task
    }

    private func waitForTurn(_ id: CGWindowID, urgent: Bool) async {
        guard !queue.request(id, urgent: urgent) else { return }
        await withCheckedContinuation { waitingForTurn[id] = $0 }
    }

    private func finishTurn(_ id: CGWindowID) {
        inFlight[id] = nil
        for next in queue.finish(id) {
            waitingForTurn.removeValue(forKey: next)?.resume()
        }
    }

    private func captureAndKeep(_ window: WindowSnapshot) async -> Kept? {
        let generation = self.generation
        let usesAtStart = freshness.usesNow(window.id)
        let signature = Self.signature(of: window)
        let start = Perf.now()
        var image = await captureOnce(window, freshList: false)
        if image == nil, !IsSecureEventInputEnabled() {
            stats.retried += 1
            try? await Task.sleep(for: Self.retryAfter)
            image = await captureOnce(window, freshList: true)
        }
        Perf.shared.record("previews.capture", since: start, detail: window.appName)
        guard let image else {
            stats.failed += 1
            return nil
        }
        let heic = await Task.detached(priority: .userInitiated) { [box = ImageBox(image)] in
            PictureCodec.compress(box.image)
        }.value
        // Dropped meanwhile (screen locked), turned private, or a password field took focus.
        guard generation == self.generation, !IsSecureEventInputEnabled() else { return nil }
        if heic == nil {
            stats.packFailed += 1
            Log.previews.notice("Could not pack a picture of \(window.appName, privacy: .public); kept as a bitmap")
        }
        let now = Date()
        let picture = Kept(heic: heic, bitmap: heic == nil ? image : nil, lastUsed: now, takenAt: now)
        kept[window.id] = picture
        freshness.pictured(window.id, as: signature, usesAtStart: usesAtStart)
        stats.captured += 1
        trim()
        return picture
    }

    /// One try. Nil, with the reason in the log (app name only, never a title), when it fails.
    private func captureOnce(_ window: WindowSnapshot, freshList: Bool) async -> CGImage? {
        guard !IsSecureEventInputEnabled() else { return nil }
        do {
            var content = try await shareableContent(fresh: freshList)
            var match = content.windows.first { $0.windowID == window.id }
            if match == nil, !freshList {
                // A window opened since the list was fetched: fetch it once more.
                content = try await shareableContent(fresh: true)
                match = content.windows.first { $0.windowID == window.id }
            }
            guard let scWindow = match, scWindow.frame.width > 0, scWindow.frame.height > 0 else {
                Log.previews.notice("Capture skipped for \(window.appName, privacy: .public): not in ScreenCaptureKit's window list")
                return nil
            }
            let scale = min(1, Self.maxPixelWidth / scWindow.frame.width)
            let configuration = SCStreamConfiguration()
            configuration.width = max(1, Int(scWindow.frame.width * scale))
            configuration.height = max(1, Int(scWindow.frame.height * scale))
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true

            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            // Re-check: a password field may have gained focus while capturing.
            guard !IsSecureEventInputEnabled() else { return nil }
            return image
        } catch {
            let error = error as NSError
            Log.previews.notice("Capture failed for \(window.appName, privacy: .public): \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            return nil
        }
    }

    private func shareableContent(fresh: Bool) async throws -> SCShareableContent {
        if !fresh, let content, Date().timeIntervalSince(content.time) < 1 { return content.value }
        if let contentTask { return try await contentTask.value.value }
        let task = Task {
            ContentBox(try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true))
        }
        contentTask = task
        defer { contentTask = nil }
        let value = try await task.value.value
        content = (value, Date())
        return value
    }

    /// The picture at `maxPixelSize`, unpacked off the main thread.
    private func unpack(_ picture: Kept, maxPixelSize: Int) async -> NSImage? {
        let cgImage: CGImage?
        if let heic = picture.heic {
            cgImage = await Task.detached(priority: .userInitiated) {
                PictureCodec.decode(heic, maxPixelSize: maxPixelSize).map(ImageBox.init)
            }.value?.image
        } else {
            cgImage = picture.bitmap
        }
        guard let cgImage else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    /// At most `maxKept` pictures: the least recently used go first.
    private func trim() {
        guard kept.count > Self.maxKept else { return }
        let oldest = kept.sorted { $0.value.lastUsed < $1.value.lastUsed }.prefix(kept.count - Self.maxKept)
        for (id, _) in oldest {
            kept[id] = nil
            freshness.forget(id)
        }
    }

    /// One line for the debug log: counts and sizes only.
    func debugLine() -> String {
        let bytes = kept.values.reduce(0) { $0 + $1.bytes }
        return "previews available=\(isAvailable) kept=\(kept.count) keptKB=\(bytes / 1024) captured=\(stats.captured) reused=\(stats.reused) failed=\(stats.failed) retried=\(stats.retried) packFailed=\(stats.packFailed) waiting=\(queue.waiting.count)"
    }
}
