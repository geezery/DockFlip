import AppKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, accessibility, previews, finish
    }

    @Published var step: Step = .welcome
    @Published var granted = Permissions.isAccessibilityTrusted
    /// nil until the user chooses — nothing is preselected.
    @Published var previews: Bool?
    @Published var nativeTilingOn = NativeEdgeTiling.isOn
    @Published var launchAtLogin = true

    var onFinish: (() -> Void)?

    var canContinue: Bool {
        switch step {
        case .welcome, .finish: return true
        case .accessibility: return granted
        case .previews: return previews != nil
        }
    }

    func next() {
        guard canContinue else { return }
        if let following = Step(rawValue: step.rawValue + 1) {
            withAnimation(.snappy(duration: 0.35)) { step = following }
        } else {
            onFinish?()
        }
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        withAnimation(.snappy(duration: 0.35)) { step = previous }
    }
}

/// First-run setup: what DockFlip is, the one required permission, the previews
/// choice (nothing preselected), and turning off macOS's own edge tiling.
/// The permission step notices the switch by events, not a timer (`AccessibilityWatch`).
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let model = OnboardingModel()
    private let watch = AccessibilityWatch()
    private var window: NSWindow?
    private var axObserver: NSObjectProtocol?
    private var activeObserver: NSObjectProtocol?
    private let onDone: () -> Void
    /// Opens Settings, where a refused Launch at login change shows its warning.
    private let showSettings: () -> Void

    init(showSettings: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.showSettings = showSettings
        self.onDone = onDone
        super.init()
        model.onFinish = { [weak self] in self?.finish() }
        model.granted = watch.granted
        watch.onChange = { [weak self] granted in
            withAnimation(.snappy) { self?.model.granted = granted }
        }
        let settings = Settings.shared
        model.launchAtLogin = SetupEnd.initialLaunchAtLogin(
            completedBefore: settings.onboardingCompleted, current: settings.launchAtLogin
        )
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.title = L("DockFlip Setup")
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: OnboardingView.width, height: OnboardingView.height))
            window.center()
            self.window = window
        }
        watch.check()
        model.nativeTilingOn = NativeEdgeTiling.isOn
        startWatching()
        if let window { WindowPresenter.bringToFront(window) }
    }

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        window = nil
        // Closed early: if the permission is there, DockFlip still starts, with the
        // choices made so far (Launch at login stays on unless it was switched off).
        if saveChoices() { onDone() }
    }

    /// Back from System Settings: the user clicked this window.
    func windowDidBecomeKey(_ notification: Notification) {
        watch.check()
    }

    private func startWatching() {
        guard axObserver == nil else { return }
        // macOS posts this whenever a switch in the Accessibility list flips.
        axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { _ = self?.watch.settingsChanged() }
        }
        // In case the announcement is missed: back from System Settings by ⌘Tab or the Dock.
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.watch.check() }
        }
    }

    private func stopWatching() {
        if let axObserver {
            DistributedNotificationCenter.default().removeObserver(axObserver)
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
        axObserver = nil
        activeObserver = nil
        watch.stop()
    }

    /// Saves what setup asked, the same way for Continue and for the close button.
    /// False when Accessibility isn't allowed: nothing is saved and DockFlip doesn't start.
    private func saveChoices() -> Bool {
        let settings = Settings.shared
        let saved = SetupEnd.save(
            previews: model.previews,
            launchAtLogin: model.launchAtLogin,
            trusted: Permissions.isAccessibilityTrusted,
            to: settings
        )
        if saved, model.previews == true, settings.previewsEnabled { PreviewProvider.requestPermission() }
        if SetupEnd.problemToShow(started: saved, settings: settings) != nil {
            Log.app.error("Setup: Launch at login didn't take; opening Settings to show why")
            showSettings()
        }
        return saved
    }

    private func finish() {
        guard saveChoices() else { return }

        stopWatching()
        window?.delegate = nil // windowWillClose must not run onDone a second time
        window?.close()
        window = nil
        onDone()
    }
}
