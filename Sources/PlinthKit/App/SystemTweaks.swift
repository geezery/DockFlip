import AppKit

/// Reads and adjusts the few system settings Plinth depends on: the Dock (whose
/// reserved space the taskbar sits on) and macOS's own edge tiling (which
/// competes with Plinth's drag snapping). Changes are only made when the user
/// presses a button for them.
enum SystemTweaks {
    private static let dock = "com.apple.dock" as CFString
    private static let windowManager = "com.apple.WindowManager" as CFString

    // MARK: Dock

    /// Bundle ids of the apps kept in the Dock, Finder first.
    static func dockPinnedBundleIDs() -> [String] {
        var ids = ["com.apple.finder"]
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, dock) as? [[String: Any]] ?? []
        for tile in tiles {
            if let data = tile["tile-data"] as? [String: Any],
               let id = data["bundle-identifier"] as? String,
               !ids.contains(id) {
                ids.append(id)
            }
        }
        return ids
    }

    /// Folders kept on the right side of the Dock (Downloads, Documents …), as paths.
    static func dockFolderPaths() -> [String] {
        let tiles = CFPreferencesCopyAppValue("persistent-others" as CFString, dock) as? [[String: Any]] ?? []
        var paths: [String] = []
        for tile in tiles {
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let urlString = file["_CFURLString"] as? String else { continue }
            let url = URL(string: urlString) ?? URL(fileURLWithPath: urlString)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
               !paths.contains(url.path) {
                paths.append(url.path)
            }
        }
        return paths
    }

    /// True when the Dock is at the bottom, always visible and not magnifying,
    /// so the taskbar can cover exactly the space the Dock reserves.
    static var isDockFitted: Bool {
        let orientation = CFPreferencesCopyAppValue("orientation" as CFString, dock) as? String ?? "bottom"
        let autohide = CFPreferencesCopyAppValue("autohide" as CFString, dock) as? Bool ?? false
        let magnification = CFPreferencesCopyAppValue("magnification" as CFString, dock) as? Bool ?? false
        let tileSize = CFPreferencesCopyAppValue("tilesize" as CFString, dock) as? Double ?? 48
        return orientation == "bottom" && !autohide && !magnification && tileSize <= 40
    }

    /// Bottom, always visible, no magnification, small icons. Restarts the Dock.
    static func fitDock() {
        CFPreferencesSetAppValue("orientation" as CFString, "bottom" as CFString, dock)
        CFPreferencesSetAppValue("autohide" as CFString, kCFBooleanFalse, dock)
        CFPreferencesSetAppValue("magnification" as CFString, kCFBooleanFalse, dock)
        CFPreferencesSetAppValue("tilesize" as CFString, NSNumber(value: 36), dock)
        CFPreferencesAppSynchronize(dock)
        restart(bundleID: "com.apple.dock")
    }

    // MARK: Native edge tiling

    /// macOS 15+ tiles windows dragged to screen edges. On by default.
    static var isNativeEdgeTilingOn: Bool {
        let edge = CFPreferencesCopyAppValue("EnableTilingByEdgeDrag" as CFString, windowManager) as? Bool ?? true
        let top = CFPreferencesCopyAppValue("EnableTopTilingByEdgeDrag" as CFString, windowManager) as? Bool ?? true
        return edge || top
    }

    static func disableNativeEdgeTiling() {
        CFPreferencesSetAppValue("EnableTilingByEdgeDrag" as CFString, kCFBooleanFalse, windowManager)
        CFPreferencesSetAppValue("EnableTopTilingByEdgeDrag" as CFString, kCFBooleanFalse, windowManager)
        CFPreferencesAppSynchronize(windowManager)
        restart(bundleID: "com.apple.WindowManager")
    }

    /// The system relaunches these agents immediately.
    private static func restart(bundleID: String) {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.forceTerminate()
        }
    }
}
