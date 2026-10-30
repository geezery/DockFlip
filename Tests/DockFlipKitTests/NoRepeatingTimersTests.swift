import Foundation
import Testing

/// CONTRIBUTING.md rule 3 and the README promise "no polling, no timers": no source file
/// may start a repeating timer. A one-shot `Task.sleep` or `repeats: false` is fine.
@Suite("House rules: no repeating timers")
struct NoRepeatingTimersTests {
    @Test func noSourceFileStartsARepeatingTimer() throws {
        // #filePath is Tests/DockFlipKitTests/NoRepeatingTimersTests.swift.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let repeating = text.range(of: #"repeats:\s*true"#, options: .regularExpression)
            #expect(repeating == nil, "\(file.lastPathComponent) starts a repeating timer")
        }
    }
}
