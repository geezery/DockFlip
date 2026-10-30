import ServiceManagement

/// DockFlip's entry in Login Items, as macOS reports it (`SMAppService.Status`).
enum LoginItemStatus: Equatable {
    case notRegistered
    case enabled
    /// Registered, but switched off in System Settings → General → Login Items.
    case requiresApproval
    case notFound
}

/// Launch at login lives in macOS, which a test can't touch: Settings goes through this.
@MainActor
protocol LoginItem {
    var status: LoginItemStatus { get }
    func register() throws
    func unregister() throws
    func openSystemSettings()
}

/// The real one: the app itself as a login item.
struct MainAppLoginItem: LoginItem {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        case .notRegistered: return .notRegistered
        @unknown default: return .notRegistered
        }
    }

    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Why the Launch at login switch didn't move, shown under it in Settings. Without
/// it the switch just flips back, and DockFlip silently doesn't start after a reboot.
enum LoginItemProblem: Equatable {
    /// The user switched DockFlip off in Login Items; only System Settings can turn it on.
    case needsApproval
    /// macOS refused, with its own words when it gave any.
    case failed(String?)

    /// The problem after asking macOS to make launch at login `wanted`.
    /// `status` is read after the attempt, `error` is what the attempt threw.
    static func after(wanting wanted: Bool, status: LoginItemStatus, error: String?) -> LoginItemProblem? {
        // A login item switched off in System Settings makes register() throw too, but
        // the status says what to do about it, so it wins over the error text.
        if wanted && status == .requiresApproval { return .needsApproval }
        if let error { return .failed(error) }
        if wanted != (status == .enabled) { return .failed(nil) }
        return nil
    }

    /// The problem once the user may have changed Login Items in System Settings: the
    /// approval note goes as soon as DockFlip is no longer waiting there. A failure
    /// stays until the switch is used again, so its words don't vanish unread.
    func refreshed(status: LoginItemStatus) -> LoginItemProblem? {
        if self == .needsApproval && status != .requiresApproval { return nil }
        return self
    }
}
