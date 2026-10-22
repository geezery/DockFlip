import Foundation

/// Selection state of the ⌘Tab switcher. Pure value type, unit-tested.
public struct SwitcherSelection: Equatable {
    public private(set) var index: Int
    public let count: Int

    /// ⌘Tab starts on the previous window (index 1); ⌘⇧Tab on the last one.
    public init(count: Int, reverse: Bool) {
        self.count = count
        if count <= 1 {
            index = 0
        } else {
            index = reverse ? count - 1 : 1
        }
    }

    public mutating func step(_ delta: Int) {
        guard count > 0 else { return }
        index = ((index + delta) % count + count) % count
    }

    public mutating func select(_ newIndex: Int) {
        guard (0..<count).contains(newIndex) else { return }
        index = newIndex
    }
}

/// Type-to-filter in the ⌘Tab switcher. Pure, unit-tested.
public enum SwitcherFilter {
    /// True when every word of `query` appears in one of `fields`, ignoring case:
    /// "team" finds "Microsoft Teams", "budj xls" finds "Budjetti.xlsx".
    /// Accents count: ä and ö are letters of their own in Finnish and Swedish, so
    /// "öö" must not find "Outlook". Composed and decomposed forms (file names
    /// often use the latter) still match each other.
    public static func matches(_ query: String, fields: [String]) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let haystack = fields.joined(separator: " ")
        return words.allSatisfy { word in
            haystack.range(of: word, options: [.caseInsensitive]) != nil
        }
    }
}
