import Testing
@testable import DockFlipKit

/// Thumbnails skip apps that show secrets and browsers' private windows.
@Suite("Thumbnails: never pictured")
struct NeverPicturedTests {
    @Test func passwordManagersAreSkipped() {
        let skipped = [
            "com.apple.keychainaccess", "com.apple.Passwords", "com.apple.systempreferences",
            "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
            "org.keepassxc.keepassxc", "com.dashlane.dashlanephonefinal", "com.lastpass.LastPass",
            "me.proton.pass.electron", "in.sinew.Enpass-Desktop", "com.markmcguill.strongbox.mac",
            "com.nordsec.nordpass", "com.hicknhacksoftware.MacPass", "com.outercorner.Secrets",
            "com.authy.authy-mac"
        ]
        #expect(NeverPictured.bundleIDs == Set(skipped))
        for id in skipped {
            #expect(NeverPictured.contains(bundleID: id, title: "Vault"))
        }
    }

    @Test func ordinaryWindowsArePictured() {
        #expect(!NeverPictured.contains(bundleID: "com.apple.TextEdit", title: "Notes - Incognito"))
        #expect(!NeverPictured.contains(bundleID: nil, title: "Private Browsing"))
        #expect(!NeverPictured.contains(bundleID: "com.google.Chrome", title: "Incognito mode explained - Wikipedia"))
        #expect(!NeverPictured.contains(bundleID: "org.mozilla.firefox", title: "News — Mozilla Firefox"))
    }

    @Test func privateBrowserWindowsAreSkipped() {
        #expect(NeverPictured.contains(bundleID: "org.mozilla.firefox", title: "News — Private Browsing"))
        #expect(NeverPictured.contains(bundleID: "org.mozilla.firefox", title: "Private Browsing"))
        #expect(NeverPictured.contains(bundleID: "com.google.Chrome", title: "News - Incognito"))
        #expect(NeverPictured.contains(bundleID: "com.google.Chrome", title: "News (Incognito)"))
        #expect(NeverPictured.contains(bundleID: "com.microsoft.edgemac", title: "News - InPrivate"))
        #expect(NeverPictured.contains(bundleID: "com.brave.Browser", title: "News - Private "))
    }
}
