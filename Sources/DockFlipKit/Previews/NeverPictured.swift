import Foundation

/// Windows thumbnails never picture, whatever the settings: apps that show
/// passwords and secrets, and browsers' private windows. Pure rules, so the
/// list is tested and the privacy pages can name it.
enum NeverPictured {
    /// Password managers, authenticators, Keychain Access and System Settings.
    static let bundleIDs: Set<String> = [
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.apple.systempreferences",
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "org.keepassxc.keepassxc",
        "com.dashlane.dashlanephonefinal",
        "com.lastpass.LastPass",
        "me.proton.pass.electron",
        "in.sinew.Enpass-Desktop",
        "com.markmcguill.strongbox.mac",
        "com.nordsec.nordpass",
        "com.hicknhacksoftware.MacPass",
        "com.outercorner.Secrets",
        "com.authy.authy-mac"
    ]

    /// Browsers that mark a private window in its title, and the word they use.
    /// Safari puts no marker in the title, so its private windows are not caught here.
    static let privateMarkers: [String: [String]] = [
        "org.mozilla.firefox": ["Private Browsing"],
        "org.mozilla.firefoxdeveloperedition": ["Private Browsing"],
        "org.mozilla.nightly": ["Private Browsing"],
        "com.google.Chrome": ["Incognito"],
        "com.google.Chrome.beta": ["Incognito"],
        "org.chromium.Chromium": ["Incognito"],
        "com.microsoft.edgemac": ["InPrivate"],
        "com.brave.Browser": ["Private", "Incognito"],
        "com.vivaldi.Vivaldi": ["Private"]
    ]

    private static let separators = [" - ", " — ", " – "]

    /// True for a window never pictured: an app in `bundleIDs`, or a browser
    /// window whose title ends in its private marker ("Page — Private Browsing",
    /// "Page - Incognito", "Page (InPrivate)").
    static func contains(bundleID: String?, title: String) -> Bool {
        guard let bundleID else { return false }
        if bundleIDs.contains(bundleID) { return true }
        guard let markers = privateMarkers[bundleID] else { return false }
        let title = title.trimmingCharacters(in: .whitespaces)
        return markers.contains { marker in
            title == marker
                || title.hasSuffix("(\(marker))")
                || separators.contains { title.hasSuffix($0 + marker) }
        }
    }
}
