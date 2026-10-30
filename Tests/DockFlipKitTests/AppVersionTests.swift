import Testing
@testable import DockFlipKit

@Suite("AppVersion")
struct AppVersionTests {
    @Test func formatAddsTheCommit() {
        #expect(AppVersion.format(version: "0.3.0", commit: "c79a704") == "0.3.0 (c79a704)")
        #expect(AppVersion.format(version: "0.3.0", commit: nil) == "0.3.0")
    }

    @Test func placeholdersAreNotShown() {
        #expect(AppVersion.cleaned("c79a704") == "c79a704")
        #expect(AppVersion.cleaned("__COMMIT__") == nil)
        #expect(AppVersion.cleaned("unknown") == nil)
        #expect(AppVersion.cleaned("") == nil)
        #expect(AppVersion.cleaned(nil) == nil)
    }
}
