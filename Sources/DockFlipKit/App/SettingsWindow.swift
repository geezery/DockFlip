import AppKit
import SwiftUI

/// The settings window: the settings from SCOPE.md and nothing more.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private lazy var screenRecording = ScreenRecordingStatus()
    private var keyObserver: NSObjectProtocol?
    var onShowSetup: (() -> Void)?
    var onRelaunch: (() -> Void)?

    func show() {
        if window == nil {
            let view = SettingsView(
                settings: Settings.shared,
                screenRecording: screenRecording,
                showSetup: { [weak self] in
                    self?.window?.close()
                    self?.onShowSetup?()
                },
                relaunch: { [weak self] in self?.onRelaunch?() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.title = L("DockFlip Settings")
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            // Coming back from System Settings brings this window forward: read the
            // Screen Recording answer again then, not on a timer.
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenRecording.refresh() }
            }
        }
        screenRecording.refresh()
        if let window { WindowPresenter.bringToFront(window) }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var screenRecording: ScreenRecordingStatus
    let showSetup: () -> Void
    let relaunch: () -> Void

    private var thumbnailAccess: ThumbnailAccess {
        ThumbnailAccess(enabled: settings.previewsEnabled, screenRecordingAllowed: screenRecording.isAllowed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section {
                    Toggle("Launch at login", isOn: Binding(
                        get: { MainActor.assumeIsolated { settings.launchAtLogin } },
                        set: { value in MainActor.assumeIsolated { settings.launchAtLogin = value } }
                    ))
                    Toggle(isOn: Binding(
                        get: { MainActor.assumeIsolated { settings.previewsEnabled } },
                        set: { value in
                            MainActor.assumeIsolated {
                                settings.previewsEnabled = value
                                if value {
                                    PreviewProvider.requestPermission()
                                    screenRecording.refresh()
                                }
                            }
                        }
                    )) {
                        Text("Window thumbnails")
                        Text("Needs the Screen & System Audio Recording permission.")
                        if settings.previewsManaged { Text("Managed by your organization") }
                    }
                    .disabled(settings.previewsManaged)
                    if thumbnailAccess == .waitingForPermission {
                        ScreenRecordingWarning(relaunch: relaunch)
                    }
                    Toggle(isOn: $settings.shortcutsEnabled) {
                        Text("Keyboard shortcuts")
                        Text("⌘Tab and the ⌃⌥ snapping shortcuts")
                        if settings.shortcutsManaged { Text("Managed by your organization") }
                    }
                    .disabled(settings.shortcutsManaged)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Button("Show Setup Again", action: showSetup)
                Spacer()
                Text(verbatim: "DockFlip \(AppVersion.display) · GPL-3.0")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Under the thumbnails switch while it is on but macOS has not allowed Screen
/// Recording: a denied prompt, or the restart macOS wants after allowing it,
/// would otherwise leave the Dock list without pictures and no word why.
struct ScreenRecordingWarning: View {
    let relaunch: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording is not allowed yet")
                    Text("Allow DockFlip in System Settings. If it is already allowed, restart DockFlip.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Open System Settings") {
                        MainActor.assumeIsolated { PreviewProvider.openScreenRecordingSettings() }
                    }
                    Button("Restart DockFlip", action: relaunch)
                }
            }
        }
    }
}
