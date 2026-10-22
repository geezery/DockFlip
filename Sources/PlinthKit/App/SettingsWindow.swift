import AppKit
import SwiftUI

/// The settings window: the settings from SCOPE.md and nothing more.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    var onShowSetup: (() -> Void)?

    func show() {
        if window == nil {
            let view = SettingsView(settings: Settings.shared) { [weak self] in
                self?.window?.close()
                self?.onShowSetup?()
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.title = L("Plinth Settings")
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        if let window { WindowPresenter.bringToFront(window) }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: Settings
    let showSetup: () -> Void

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
                                if value { PreviewProvider.requestPermission() }
                            }
                        }
                    )) {
                        Text("Window thumbnails")
                        Text("Needs the Screen & System Audio Recording permission.")
                    }
                }
                Section {
                    Picker(selection: $settings.useDock) {
                        Text("macOS Dock").tag(true)
                        Text("Plinth taskbar").tag(false)
                    } label: {
                        Text("Taskbar")
                        Text("Changing this restarts Plinth.")
                    }
                    if !settings.useDock {
                        Picker("Combine taskbar buttons", selection: $settings.combineButtons) {
                            Text("Always").tag(true)
                            Text("Never").tag(false)
                        }
                        Toggle("Show taskbar on all displays", isOn: $settings.taskbarOnAllDisplays)
                    }
                    Toggle(isOn: $settings.shortcutsEnabled) {
                        Text("Keyboard shortcuts")
                        Text("⌘Tab and the ⌃⌥ snapping shortcuts")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)

            HStack {
                Button("Show Setup Again", action: showSetup)
                Spacer()
                Text("Plinth \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") · GPL-3.0")
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
