import CoreGraphics

/// The Snap Assist panel's grid of window cards, pure and unit-tested: how many
/// cards fit in the region left after a snap, and how the arrow keys move the
/// selection among them. The panel (`SnapAssistPanel`) only draws what this says.
///
/// Unlike the ⌘Tab grid, every card here has the same size, so the cards line up
/// in columns and ↑ / ↓ go to the card straight above or below.
public struct SnapAssistGrid: Equatable {
    /// Around each card's icon, title and picture (as `SwitcherGrid.tilePadding`).
    public static let tilePadding = 8.0
    /// The icon and title above the picture, with the gap under them.
    public static let headerHeight = 24.0
    /// Between cards and between rows.
    public static let spacing = 12.0
    /// Kept clear between the region's edge and the cards.
    public static let margin = 24.0
    /// A card's picture is 16:10, the shape of most windows.
    public static let pictureAspect = 1.6

    /// The height of every card's picture.
    public let pictureHeight: Double
    /// Every card's full width, padding included.
    public let tileWidth: Double
    /// Cards in a row.
    public let columns: Int
    /// The most cards shown: as many as fit, the least recently used left out.
    public let capacity: Int

    /// The grid for a region of `region` points.
    public init(region: CGSize) {
        let width = max(Double(region.width) - 2 * Self.margin, 0)
        let height = max(Double(region.height) - 2 * Self.margin, 0)
        // Smaller pictures in a quarter than in a half, but never too small to tell apart.
        let picture = min(max(height * 0.16, 72), 140)
        pictureHeight = picture
        tileWidth = picture * Self.pictureAspect + 2 * Self.tilePadding
        let tileHeight = picture + Self.headerHeight + 2 * Self.tilePadding
        columns = max(Int((width + Self.spacing) / (tileWidth + Self.spacing)), 1)
        let rows = max(Int((height + Self.spacing) / (tileHeight + Self.spacing)), 1)
        capacity = columns * rows
    }

    /// The rows of `count` cards, in order, `columns` to a row.
    public func rows(count: Int) -> [Range<Int>] {
        stride(from: 0, to: max(count, 0), by: columns).map { $0..<min($0 + columns, count) }
    }

    /// Where an arrow key moves the selection from `index` among `count` cards.
    /// ← / → go to the previous and next card, across rows; ↑ / ↓ to the card
    /// above or below. At an edge the selection stays (as on Windows), except ↓
    /// into a shorter last row, which goes to its last card.
    public func move(_ key: SnapKey, from index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let current = min(max(index, 0), count - 1)
        switch key {
        case .left: return max(current - 1, 0)
        case .right: return min(current + 1, count - 1)
        case .up: return current >= columns ? current - columns : current
        case .down:
            let lastRowStart = (count - 1) / columns * columns
            return current < lastRowStart ? min(current + columns, count - 1) : current
        }
    }
}

/// What a key pressed while the Snap Assist panel is shown does.
public enum SnapAssistKey: Equatable {
    case move(SnapKey)
    case pick
    case dismiss

    /// Arrows, Return and Esc without modifiers; nil lets the key go by. Keys
    /// with ⌃ or ⌥ or ⌘ are DockFlip's or the system's shortcuts: a ⌃⌥ arrow is
    /// the next snap, which closes the panel itself.
    public static func from(keyCode: UInt32, hasShortcutModifiers: Bool) -> SnapAssistKey? {
        guard !hasShortcutModifiers else { return nil }
        switch keyCode {
        case KeyCode.left: return .move(.left)
        case KeyCode.right: return .move(.right)
        case KeyCode.up: return .move(.up)
        case KeyCode.down: return .move(.down)
        case KeyCode.returnKey, KeyCode.keypadEnter: return .pick
        case KeyCode.escape: return .dismiss
        default: return nil
        }
    }
}
