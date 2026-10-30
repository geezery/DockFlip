import Testing
@testable import DockFlipKit

@Suite("BrowserTabs")
struct BrowserTabsTests {
    @Test(arguments: [
        "com.apple.Safari", "com.google.Chrome", "com.microsoft.edgemac", "org.mozilla.firefox",
        "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "org.chromium.Chromium", "company.thebrowser.Browser", "app.zen-browser.zen",
        "com.kagi.kagimacOS", "com.kagi.kagimacOS.RC", "com.duckduckgo.macos.browser",
        "com.apple.finder", "com.apple.Terminal"
    ])
    func readsTabsOf(_ bundleID: String) {
        #expect(BrowserTabs.hasTabs(bundleID))
    }

    @Test func leavesOtherAppsAlone() {
        // Office ribbons are tab groups too: listing them would be noise.
        #expect(!BrowserTabs.hasTabs("com.microsoft.Word"))
        #expect(!BrowserTabs.hasTabs("com.apple.TextEdit"))
        #expect(!BrowserTabs.hasTabs(nil))
    }
}
