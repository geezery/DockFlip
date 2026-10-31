import AppKit
import SwiftUI

/// The settings window: the settings from SCOPE.md and nothing more.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private lazy var screenRecording = ScreenRecordingStatus()
    private var keyObserver: NSObjectProtocol?
    /// The running features, to say which shortcuts another app holds.
    var services: () -> Services? = { nil }
    private lazy var shortcutConflicts = ShortcutConflictStatus(services: { [weak self] in self?.services() })
    var onShowSetup: (() -> Void)?
    var onRelaunch: (() -> Void)?

    func show() {
        if window == nil {
            let view = SettingsView(
                settings: Settings.shared,
                screenRecording: screenRecording,
                shortcutConflicts: shortcutConflicts,
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
            // Screen Recording and Login Items answers again then, not on a timer.
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.screenRecording.refresh()
                    Settings.shared.refreshLaunchAtLogin()
                    self?.shortcutConflicts.refresh()
                }
            }
        }
        screenRecording.refresh()
        Settings.shared.refreshLaunchAtLogin()
        shortcutConflicts.refresh()
        if let window { WindowPresenter.bringToFront(window) }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var screenRecording: ScreenRecordingStatus
    @ObservedObject var shortcutConflicts: ShortcutConflictStatus
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
                    if let problem = settings.launchAtLoginProblem {
                        LaunchAtLoginWarning(problem: problem) {
                            MainActor.assumeIsolated { settings.openLoginItemsSettings() }
                        }
                    }
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
                    if let warning = shortcutConflicts.warning {
                        ShortcutConflictWarningRow(warning: warning) {
                            MainActor.assumeIsolated { shortcutConflicts.tryAgain() }
                        }
                    }
                    SwitcherStylePicker(settings: settings)
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

/// The ⌘Tab look: Flip 3D or the Windows 11 grid. Greyed out while the keyboard
/// shortcuts are off (there is no ⌘Tab then) or when a profile manages it.
struct SwitcherStylePicker: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Picker(selection: $settings.switcherStyle) {
            Text("Flip 3D").tag(SwitcherStyle.flip3D)
            Text("Grid").tag(SwitcherStyle.grid)
        } label: {
            Text("⌘Tab switcher")
            Text("Flip 3D as in Windows 7, or a grid as in Windows 11")
            if settings.switcherStyleManaged { Text("Managed by your organization") }
        }
        .disabled(settings.switcherStyleManaged || !settings.shortcutsEnabled)
    }
}

/// A warning under a Settings switch: what is wrong, what to do, and the buttons
/// that do it. Every warning shares it so they look alike.
struct SettingsWarningRow<Actions: View>: View {
    let title: Text
    let detail: Text
    let actions: Actions

    init(title: Text, detail: Text, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.detail = detail
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    title
                    detail
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                actions
            }
        }
    }
}

/// Under the thumbnails switch while it is on but macOS has not allowed Screen
/// Recording: a denied prompt, or the restart macOS wants after allowing it,
/// would otherwise leave the Dock list without pictures and no word why.
struct ScreenRecordingWarning: View {
    let relaunch: () -> Void

    var body: some View {
        SettingsWarningRow(
            title: Text("Screen Recording is not allowed yet"),
            detail: Text("Allow DockFlip in System Settings. If it is already allowed, restart DockFlip.")
        ) {
            HStack {
                Button("Open System Settings") {
                    MainActor.assumeIsolated { PreviewProvider.openScreenRecordingSettings() }
                }
                Button("Restart DockFlip", action: relaunch)
            }
        }
    }
}

/// Under the Launch at login switch when macOS didn't take the change: the switch
/// only flips back, and DockFlip would quietly not start after the next reboot.
struct LaunchAtLoginWarning: View {
    let problem: LoginItemProblem
    let openLoginItems: () -> Void

    var body: some View {
        SettingsWarningRow(title: title, detail: detail) {
            Button("Open Login Items", action: openLoginItems)
        }
    }

    private var title: Text {
        switch problem {
        case .needsApproval: return Text("DockFlip is switched off in Login Items")
        case .failed: return Text("Launch at login could not be changed")
        }
    }

    private var detail: Text {
        switch problem {
        case .needsApproval:
            return Text("Open Login Items and switch DockFlip on there to start it when you log in.")
        case .failed(let reason):
            // macOS's own words, already in the user's language.
            if let reason { return Text(verbatim: reason) }
            return Text("macOS did not accept the change.")
        }
    }
}
