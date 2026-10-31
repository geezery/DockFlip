import Foundation

/// Finds the localization keys DockFlip's code uses by reading its Swift source,
/// so a test can check each one has an entry in `en.lproj/Localizable.strings`.
///
/// It reads the shapes the code uses today:
/// - `L("…")` in AppKit;
/// - the first string literal of `Text`, `Button`, `Toggle`, `Label`, `Section`
///   and `LocalizedStringKey(…)` in SwiftUI;
/// - a literal passed to a view's `LocalizedStringKey` property by its label
///   (`StepHeader(title: "…", subtitle: "…")`), the labels found in the source itself;
/// - a literal assigned to a `LocalizedStringKey` (`let x: LocalizedStringKey = "…"`)
///   or written in the body of a computed one (`var title: LocalizedStringKey { … }`).
///
/// It skips comment lines, empty keys and literals with `\(…)`: SwiftUI turns those
/// into format keys (`%lld`), and the code builds its counted texts with
/// `String(format: L("… %ld …"))` instead, which the `L("…")` shape covers.
enum SourceStringKeys {
    /// Keys the code shows the same in every language, so they need no entry.
    static let sameInEveryLanguage: Set<String> = [
        "⌘Tab" // the shortcut's name on the Welcome step's feature card
    ]

    /// Every key the `.swift` files under `folder` use, each with the name of
    /// the first file (in name order) it appears in.
    static func scan(_ folder: URL) throws -> [String: String] {
        let paths = try FileManager.default.subpathsOfDirectory(atPath: folder.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        var sources: [(name: String, text: String)] = []
        for path in paths {
            let url = folder.appendingPathComponent(path)
            let text = try String(contentsOf: url, encoding: .utf8)
            sources.append((url.lastPathComponent, text))
        }
        // A view's LocalizedStringKey property is declared in one file and given its text in another.
        var labels: Set<String> = []
        for source in sources {
            let declared = try keyProperties(in: source.text)
            labels.formUnion(declared)
        }
        var found: [String: String] = [:]
        for source in sources {
            for key in try keys(in: source.text, labels: labels) where found[key] == nil {
                found[key] = source.name
            }
        }
        return found
    }

    /// The keys `used` names that `english` lacks, sorted, leaving out `sameInEveryLanguage`.
    static func missing(_ used: some Sequence<String>, from english: Set<String>) -> [String] {
        let absent = used.filter { !english.contains($0) && !sameInEveryLanguage.contains($0) }
        return Set(absent).sorted()
    }

    /// The names of the `LocalizedStringKey` properties `source` declares
    /// (`let title: LocalizedStringKey`), not the computed ones.
    static func keyProperties(in source: String) throws -> Set<String> {
        let names = try matches(#"\b(?:let|var)\s+(\w+)\s*:\s*LocalizedStringKey\b(?![ \t]*\{)"#, in: source)
        return Set(names)
    }

    /// The keys `source` uses, in the order found; `labels` are the argument
    /// labels that take a `LocalizedStringKey` (see `keyProperties`).
    static func keys(in source: String, labels: Set<String>) throws -> [String] {
        let code = source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        var patterns = [
            #"(?<![\w.])(?:L|Text|Button|Toggle|Label|Section|LocalizedStringKey)\(\s*"# + literal,
            #":\s*LocalizedStringKey\s*=\s*"# + literal
        ]
        if !labels.isEmpty {
            patterns.append(#"(?<![\w.])(?:"# + labels.sorted().joined(separator: "|") + #"):\s*"# + literal)
        }
        var found: [String] = []
        for pattern in patterns {
            found += try matches(pattern, in: code)
        }
        found += try computedKeys(in: code)
        return found
            .filter { !$0.isEmpty && !$0.contains(#"\("#) }
            .map(unescape)
    }

    /// A Swift string literal on one line; group 1 is its text with the escapes still in.
    static let literal = #""((?:[^"\\\n]|\\.)*)""#

    /// Every literal in the bodies of computed `LocalizedStringKey`s
    /// (`var title: LocalizedStringKey { switch … return "…" }`).
    static func computedKeys(in code: String) throws -> [String] {
        let text = code as NSString
        let opener = try NSRegularExpression(pattern: #"(?::|->)\s*LocalizedStringKey[ \t]*\{"#)
        var found: [String] = []
        for match in opener.matches(in: code, range: NSRange(location: 0, length: text.length)) {
            let start = match.range.location + match.range.length
            var end = start
            var depth = 1
            // Braces inside string literals would throw this count off; the code has none there.
            while depth > 0 && end < text.length {
                let character = text.character(at: end)
                if character == 0x7B { depth += 1 } else if character == 0x7D { depth -= 1 }
                end += 1
            }
            let body = text.substring(with: NSRange(location: start, length: end - start))
            found += try matches(literal, in: body)
        }
        return found
    }

    /// Group 1 of every match of `pattern` in `text`.
    static func matches(_ pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The text a literal stands for: `\"` is `"`, `\n` a line break.
    static func unescape(_ literal: String) -> String {
        var text = ""
        var escaped = false
        for character in literal {
            if escaped {
                switch character {
                case "n": text.append("\n")
                case "t": text.append("\t")
                default: text.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                text.append(character)
            }
        }
        return text
    }
}
