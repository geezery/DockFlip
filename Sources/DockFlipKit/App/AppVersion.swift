import Foundation

/// Which DockFlip this is, read from the bundle's Info.plist. A build from source
/// keeps the Makefile's version number, so the git commit it was built from
/// (`DockFlipCommit`, filled in by `make app`) is what tells two builds apart.
enum AppVersion {
    static var version: String { info("CFBundleShortVersionString") ?? "?" }
    static var build: String { info("CFBundleVersion") ?? "?" }
    static var commit: String? { info("DockFlipCommit") }

    /// "0.3.0 (c79a704)", or "0.3.0" when the commit is unknown.
    static var display: String { format(version: version, commit: commit) }

    static func format(version: String, commit: String?) -> String {
        guard let commit else { return version }
        return "\(version) (\(commit))"
    }

    /// A plist value worth showing: a plist that was never filled in (`swift run`,
    /// a build without git) still holds its placeholder or "unknown".
    static func cleaned(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.hasPrefix("__"), value != "unknown" else { return nil }
        return value
    }

    private static func info(_ key: String) -> String? {
        cleaned(Bundle.main.object(forInfoDictionaryKey: key) as? String)
    }
}
