import Foundation
import Testing
@testable import DockFlipKit

@Suite("DebugLogFile")
struct DebugLogFileTests {
    @Test func suggestedNameCarriesTheTime() {
        let date = Date(timeIntervalSince1970: 1_793_370_301) // 2026-10-30 14:25:01 UTC
        let utc = TimeZone(identifier: "UTC")!
        #expect(DebugLogFile.suggestedName(at: date, timeZone: utc) == "DockFlip-debug-20261030-142501.txt")
    }

    @Test func writeSavesTheText() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DockFlip-debug-test-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try DebugLogFile.write("DockFlip debug log\n⌘Tab", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "DockFlip debug log\n⌘Tab")
    }

    /// A failed write throws instead of failing quietly, and the alert gets a reason to show.
    @Test func failedWriteGivesAReason() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("no-such-folder-\(UUID().uuidString)")
            .appendingPathComponent("DockFlip-debug.txt")
        do {
            try DebugLogFile.write("log", to: url)
            Issue.record("Writing into a missing folder succeeded")
        } catch {
            let text = DebugLogFile.failureText(for: error, fileName: url.lastPathComponent)
            #expect(!text.isEmpty)
            #expect(text == error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    @Test func failureTextFallsBackToTheFileName() {
        let silent = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: " "])
        #expect(DebugLogFile.failureText(for: silent, fileName: "DockFlip-debug.txt") == "DockFlip-debug.txt")
    }
}
