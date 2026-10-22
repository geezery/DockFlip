import AppKit
import SwiftUI

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var granted = Permissions.isAccessibilityTrusted
    var onContinue: (() -> Void)?
}

/// First-run window. Asks for the one permission Plinth needs; services start
/// on Continue, or when the window is closed after the permission was granted.
/// The only timer in the app lives here, and only while this window is open.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private let model = OnboardingModel()
    private var window: NSWindow?
    private var timer: Timer?
    private var axObserver: NSObjectProtocol?
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted
        super.init()
        model.onContinue = { [weak self] in self?.finish() }
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            let window = NSWindow(contentViewController: hosting)
            window.title = L("Plinth Setup")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        startWatching()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        stopWatching()
        // Granted in System Settings, then closed with the red button: start anyway.
        if Permissions.isAccessibilityTrusted {
            window = nil
            onGranted()
        }
    }

    private func startWatching() {
        guard timer == nil else { return }
        // Posted by the system when any app's Accessibility trust changes.
        axObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The trust value updates slightly after the notification.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                self?.check()
            }
        }
        // Fallback in case the notification is missed.
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
            model.granted = trusted
        }
    }

    private func finish() {
        guard Permissions.isAccessibilityTrusted else { return }
        stopWatching()
        window?.delegate = nil // windowWillClose must not call onGranted a second time
        window?.close()
        window = nil
        onGranted()
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Welcome to Plinth")
                .font(.system(size: 24, weight: .bold))

            Text("Plinth brings the Windows taskbar, Alt-Tab window switching and window snapping to your Mac. It needs one permission to work: Accessibility.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Accessibility is used to list, focus, move and minimize windows, and for the ⌥Tab and ⌃⌥ shortcuts.")
                .font(.system(size: 13))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Label {
                    Text(model.granted
                         ? LocalizedStringKey("Accessibility: allowed")
                         : LocalizedStringKey("Accessibility: not yet allowed"))
                } icon: {
                    Image(systemName: model.granted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(model.granted ? Color.green : Color.secondary)
                }
                .font(.system(size: 13, weight: .semibold))

                if !model.granted {
                    Button("Open System Settings") {
                        Permissions.requestAccessibility()
                    }
                    .controlSize(.large)
                }
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue") {
                    model.onContinue?()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(!model.granted)
            }
        }
        .padding(28)
        .frame(width: 560, height: 360)
    }
}
