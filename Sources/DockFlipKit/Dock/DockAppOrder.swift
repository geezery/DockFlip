import Foundation

/// Which app ⌃⌥1…9 means: the n-th app icon in the Dock, counted from the start
/// and skipping folders, the Trash and separators. Pure, unit-tested.
///
/// Every key press asks the Dock, so its order is always the one on screen; to
/// keep the press quick, each icon is read only until the n-th app is found.
enum DockAppOrder {
    /// The bundle ID of the app at `index` (0-based) among `items`. `bundleID`
    /// reads one icon (nil for anything that is not an app) and is called for
    /// the icons up to that app only.
    static func app<Item>(at index: Int, in items: [Item], bundleID: (Item) -> String?) -> String? {
        guard index >= 0 else { return nil }
        var apps = 0
        for item in items {
            guard let id = bundleID(item) else { continue }
            if apps == index { return id }
            apps += 1
        }
        return nil
    }
}

/// Bundle IDs by app URL, so an app's Info.plist is read once, not on every
/// ⌃⌥1…9 press. A failed read is not kept: the next press tries again.
struct BundleIDCache {
    private var known: [URL: String] = [:]

    mutating func bundleID(for url: URL, resolve: (URL) -> String?) -> String? {
        if let id = known[url] { return id }
        guard let id = resolve(url) else { return nil }
        known[url] = id
        return id
    }
}
