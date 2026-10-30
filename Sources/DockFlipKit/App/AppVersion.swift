import Foundation

/// Which DockFlip this is, read from the bundle's Info.plist. A build from source
/// keeps the Makefile's version number, so the git commit it was built from
/// (`DockFlipCommit`, filled in by `make app`) is what tells two builds apart.
enum AppVersion {
    static var version: String { info("CFBundleShortVersionString") ?? "?" }
    static var build: String { info("CFBundleVersion") ?? "?" }
    static var commit: String? { info("DockFlipCommit") }

    /// "0.3.0 (c79a704)", or "0.3.0" when the commit is unknown.
    static var display: String {
        guard let commit else { return version }
        return "\(version) (\(commit))"
    }

    private static func info(_ key: String) -> String? {
        // A plist that was never filled in (`swift run`, no git) still holds its placeholder.
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty, !value.hasPrefix("__"), value != "unknown" else { return nil }
        return value
    }
}
