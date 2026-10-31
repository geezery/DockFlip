import AppKit
import Combine
import SwiftUI

/// Which of DockFlip's shortcuts another app holds, for the Settings window. Read
/// when the window comes forward, after the switch changes and after Try Again:
/// macOS sends no word when another app lets go of a hot key, so no timer either.
@MainActor
final class ShortcutConflictStatus: ObservableObject {
    @Published private(set) var warning: ShortcutConflicts.Warning?
    private let services: () -> Services?
    private var subscription: AnyCancellable?

    init(services: @escaping () -> Services?) {
        self.services = services
        subscription = Settings.shared.$shortcutsEnabled.dropFirst().sink { [weak self] _ in
            // AppDelegate applies the switch on the next turn: read after it.
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        guard let services = services() else {
            warning = nil
            return
        }
        warning = ShortcutConflicts.warning(
            commandTabHeld: services.commandTabHeldElsewhere,
            layoutHeld: services.layoutShortcutsHeldElsewhere,
            bundleIDs: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
    }

    /// Asks for the shortcuts again, once the other app has quit or let go.
    func tryAgain() {
        guard let services = services() else { return }
        Log.keys.notice("Shortcuts asked for again from Settings")
        services.applyShortcutSetting()
        refresh()
    }
}

/// Under the Keyboard shortcuts switch when another app (AltTab, Rectangle) holds
/// some of them: the switch is on, yet ⌘Tab or ⌃⌥← does the other app's thing,
/// and people look in Settings first.
struct ShortcutConflictWarningRow: View {
    let warning: ShortcutConflicts.Warning
    let tryAgain: () -> Void

    var body: some View {
        SettingsWarningRow(
            title: Text(verbatim: String(format: L("%@: used by another app"), warning.shortcuts.joined(separator: " "))),
            detail: Text(verbatim: detail)
        ) {
            Button("Try Again", action: tryAgain)
        }
    }

    private var detail: String {
        warning.apps.isEmpty
            ? L("Quit the app that uses them, then try again.")
            : String(format: L("Probably %@. Quit it or change its shortcuts, then try again."),
                     warning.apps.joined(separator: ", "))
    }
}
