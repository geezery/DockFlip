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
/// The only timer in the app lives here, and only while this window is open.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let model = OnboardingModel()
    private var window: NSWindow?
    private var timer: Timer?
    private var axObserver: NSObjectProtocol?
    private let onDone: () -> Void

    init(onDone: @escaping () -> Void) {
        self.onDone = onDone
        super.init()
        model.onFinish = { [weak self] in self?.finish() }
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
        model.granted = Permissions.isAccessibilityTrusted
        model.nativeTilingOn = NativeEdgeTiling.isOn
        startWatching()
        if let window { WindowPresenter.bringToFront(window) }
    }

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        window = nil
        // Closed early: if the permission is there, DockFlip still starts.
        if Permissions.isAccessibilityTrusted {
            Settings.shared.onboardingCompleted = true
            onDone()
        }
    }

    private func startWatching() {
        guard timer == nil else { return }
        axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.check()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        if let axObserver {
            DistributedNotificationCenter.default().removeObserver(axObserver)
        }
        axObserver = nil
    }

    private func check() {
        let trusted = Permissions.isAccessibilityTrusted
        if trusted != model.granted {
            withAnimation(.snappy) { model.granted = trusted }
        }
    }

    private func finish() {
        guard Permissions.isAccessibilityTrusted else { return }
        let settings = Settings.shared
        settings.previewsEnabled = model.previews ?? false
        if settings.previewsEnabled { PreviewProvider.requestPermission() }
        if model.launchAtLogin != settings.launchAtLogin { settings.launchAtLogin = model.launchAtLogin }
        settings.onboardingCompleted = true

        stopWatching()
        window?.delegate = nil // windowWillClose must not run onDone a second time
        window?.close()
        window = nil
        onDone()
    }
}
