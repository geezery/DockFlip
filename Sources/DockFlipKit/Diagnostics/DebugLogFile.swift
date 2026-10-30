import Foundation

/// The debug log on disk: its suggested name and the write. No AppKit, so the
/// tests reach it; the save panel and the alert are in `Diagnostics`.
enum DebugLogFile {
    /// "DockFlip-debug-20261030-142501.txt": sorts by time, and says what it is
    /// when it lands in a bug report.
    static func suggestedName(at date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        // Fixed digits whatever calendar and numbering the user's region has.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "DockFlip-debug-\(formatter.string(from: date)).txt"
    }

    /// Writes the log. The error is the system's own, already in the user's
    /// language, and goes into the alert as it is.
    static func write(_ text: String, to url: URL) throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The alert's text for a failed write: the system's reason, or the file's
    /// name when the error says nothing.
    static func failureText(for error: Error, fileName: String) -> String {
        let reason = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? fileName : reason
    }
}
