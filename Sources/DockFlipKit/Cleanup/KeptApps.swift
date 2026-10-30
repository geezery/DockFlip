import Foundation

/// The apps Clean Up never suggests ("Never suggest this app again"), as the bundle
/// ids kept in the defaults. Apart from AppKit so it can be tested.
struct KeptApps: Equatable {
    /// Sorted, each id once: the form they are stored in.
    private(set) var bundleIDs: [String]

    init(_ stored: [String]) {
        bundleIDs = Array(Set(stored)).sorted()
    }

    var set: Set<String> { Set(bundleIDs) }

    mutating func add(_ bundleID: String) {
        guard !bundleIDs.contains(bundleID) else { return }
        bundleIDs = (bundleIDs + [bundleID]).sorted()
    }

    /// The app is suggested again, by the same rules as any other app.
    mutating func remove(_ bundleID: String) {
        bundleIDs.removeAll { $0 == bundleID }
    }
}
