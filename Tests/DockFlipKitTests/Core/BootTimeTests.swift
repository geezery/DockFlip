import Foundation
import Testing
@testable import DockFlipKit

@Suite("BootTime")
struct BootTimeTests {
    /// Window ids are reused after the Mac restarts: only this boot's ids are trusted.
    @Test func onlyThisBootIsTrusted() {
        let boot: TimeInterval = 1_800_000_000
        #expect(BootTime.isSameBoot(saved: boot, now: boot))
        #expect(BootTime.isSameBoot(saved: boot - 2, now: boot))
        #expect(BootTime.isSameBoot(saved: boot + 2, now: boot))
        #expect(!BootTime.isSameBoot(saved: boot - 3_600, now: boot))
        #expect(!BootTime.isSameBoot(saved: 0, now: boot)) // never saved
    }

    /// When sysctl fails the boot time reads as 0, and nothing saved can be matched to it.
    @Test func unreadableBootTimeTrustsNothing() {
        #expect(!BootTime.isSameBoot(saved: 0, now: 0))
        #expect(!BootTime.isSameBoot(saved: 1_800_000_000, now: 0))
        #expect(!BootTime.isSameBoot(saved: 30, now: 0)) // within the slack of 0, still not trusted
    }

    /// The real boot time is in the past and matches itself.
    @Test func realBootTimeIsReadable() {
        let boot = BootTime.now()
        #expect(boot > 0)
        #expect(boot <= Date().timeIntervalSince1970)
        #expect(BootTime.isSameBoot(saved: boot))
    }
}
