import CoreGraphics

/// Where a window can be snapped. Windows 11 parity only: halves, quarters, maximized.
public enum SnapRegion: Equatable, CaseIterable {
    case leftHalf, rightHalf, maximized
    case topLeft, topRight, bottomLeft, bottomRight
}

/// What a ⌃⌥-arrow press should do.
public enum SnapAction: Equatable {
    case snap(SnapRegion, display: Int)
    case restore
    case minimize
    case none
}

/// Pure snapping logic, unit-tested. Rectangles are in AX space (top-left origin).
public enum SnapEngine {
    /// Windows 11 keyboard snapping as a state machine.
    /// `current` is nil for a free (unsnapped) window. Displays are ordered left to right.
    public static func action(for key: SnapKey, current: SnapRegion?, display: Int, displayCount: Int) -> SnapAction {
        let hasLeft = display > 0
        let hasRight = display < displayCount - 1

        switch key {
        case .left:
            switch current {
            case nil: return .snap(.leftHalf, display: display)
            case .rightHalf?: return .restore
            case .maximized?: return .snap(.leftHalf, display: display)
            case .topRight?: return .snap(.topLeft, display: display)
            case .bottomRight?: return .snap(.bottomLeft, display: display)
            case .leftHalf?: return hasLeft ? .snap(.rightHalf, display: display - 1) : .none
            case .topLeft?: return hasLeft ? .snap(.topRight, display: display - 1) : .none
            case .bottomLeft?: return hasLeft ? .snap(.bottomRight, display: display - 1) : .none
            }
        case .right:
            switch current {
            case nil: return .snap(.rightHalf, display: display)
            case .leftHalf?: return .restore
            case .maximized?: return .snap(.rightHalf, display: display)
            case .topLeft?: return .snap(.topRight, display: display)
            case .bottomLeft?: return .snap(.bottomRight, display: display)
            case .rightHalf?: return hasRight ? .snap(.leftHalf, display: display + 1) : .none
            case .topRight?: return hasRight ? .snap(.topLeft, display: display + 1) : .none
            case .bottomRight?: return hasRight ? .snap(.bottomLeft, display: display + 1) : .none
            }
        case .up:
            switch current {
            case nil: return .snap(.maximized, display: display)
            case .leftHalf?: return .snap(.topLeft, display: display)
            case .rightHalf?: return .snap(.topRight, display: display)
            case .bottomLeft?: return .snap(.leftHalf, display: display)
            case .bottomRight?: return .snap(.rightHalf, display: display)
            case .maximized?, .topLeft?, .topRight?: return .none
            }
        case .down:
            switch current {
            case .maximized?: return .restore
            case nil: return .minimize
            case .leftHalf?: return .snap(.bottomLeft, display: display)
            case .rightHalf?: return .snap(.bottomRight, display: display)
            case .topLeft?: return .snap(.leftHalf, display: display)
            case .topRight?: return .snap(.rightHalf, display: display)
            case .bottomLeft?, .bottomRight?: return .minimize
            }
        }
    }

    /// The rectangle of `region` inside the usable `area` of a display.
    public static func rect(for region: SnapRegion, in area: CGRect) -> CGRect {
        let halfWidth = (area.width / 2).rounded(.down)
        let halfHeight = (area.height / 2).rounded(.down)
        let left = CGRect(x: area.minX, y: area.minY, width: halfWidth, height: area.height)
        let right = CGRect(x: area.minX + halfWidth, y: area.minY, width: area.width - halfWidth, height: area.height)
        switch region {
        case .maximized: return area
        case .leftHalf: return left
        case .rightHalf: return right
        case .topLeft: return CGRect(x: left.minX, y: area.minY, width: left.width, height: halfHeight)
        case .bottomLeft: return CGRect(x: left.minX, y: area.minY + halfHeight, width: left.width, height: area.height - halfHeight)
        case .topRight: return CGRect(x: right.minX, y: area.minY, width: right.width, height: halfHeight)
        case .bottomRight: return CGRect(x: right.minX, y: area.minY + halfHeight, width: right.width, height: area.height - halfHeight)
        }
    }

    /// Which region `frame` currently fills, if any. Apps round sizes to their own
    /// increments (terminals, editors), hence the tolerance.
    public static func region(matching frame: CGRect, in area: CGRect, tolerance: CGFloat = 24) -> SnapRegion? {
        SnapRegion.allCases.first { region in
            let target = rect(for: region, in: area)
            return abs(frame.minX - target.minX) <= tolerance
                && abs(frame.minY - target.minY) <= tolerance
                && abs(frame.width - target.width) <= tolerance
                && abs(frame.height - target.height) <= tolerance
        }
    }

    /// Keeps a free window's position relative to its display when it moves to another one.
    public static func translate(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        let width = min(frame.width, target.width)
        let height = min(frame.height, target.height)
        let relX = (frame.minX - source.minX) / source.width
        let relY = (frame.minY - source.minY) / source.height
        let x = min(max(target.minX + relX * target.width, target.minX), target.maxX - width)
        let y = min(max(target.minY + relY * target.height, target.minY), target.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// A sensible free frame when there is nothing to restore: two thirds, centered.
    public static func defaultFreeFrame(in area: CGRect) -> CGRect {
        let width = (area.width * 2 / 3).rounded()
        let height = (area.height * 2 / 3).rounded()
        return CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height)
    }
}
