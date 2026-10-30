import CoreGraphics
import Foundation

/// The remembered layouts, one per display set, apart from AppKit so their rules and
/// the form they are saved in can be tested. Kept in UserDefaults so they survive a
/// DockFlip restart (a language change, an update, a crash); window ids stay valid only
/// until the Mac restarts, so the saved form is tied to the boot time.
struct PlacementLayouts: Equatable {
    static let maxLayouts = 8

    /// Display-set signature → window id → frame (AX space).
    private(set) var layouts: [String: [CGWindowID: CGRect]] = [:]
    /// Signatures, least recently saved first.
    private(set) var order: [String] = []

    subscript(signature: String) -> [CGWindowID: CGRect]? {
        layouts[signature]
    }

    /// Keeps `layout` for `signature` as the newest, and forgets the oldest past `maxLayouts`.
    mutating func set(_ layout: [CGWindowID: CGRect], for signature: String) {
        layouts[signature] = layout
        order.removeAll { $0 == signature }
        order.append(signature)
        while order.count > Self.maxLayouts {
            layouts[order.removeFirst()] = nil
        }
    }

    /// Forgets windows that no longer exist, in every display set's layout: their ids
    /// would otherwise pile up in the saved form until the Mac restarts.
    mutating func keepOnly(_ alive: Set<CGWindowID>) {
        for (signature, layout) in layouts {
            layouts[signature] = layout.filter { alive.contains($0.key) }
        }
    }

    // MARK: - Saved form

    /// A property list: the layouts in `order`, each `["signature": …, "frames": [id: [x, y, w, h]]]`.
    var propertyList: [[String: Any]] {
        order.compactMap { signature in
            guard let layout = layouts[signature] else { return nil }
            let frames = Dictionary(uniqueKeysWithValues: layout.map { id, frame in
                (String(id), [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)])
            })
            return ["signature": signature, "frames": frames]
        }
    }

    /// Reads `propertyList` back. Anything it doesn't recognise is skipped, never trusted.
    init(propertyList: Any?) {
        guard let entries = propertyList as? [[String: Any]] else { return }
        for entry in entries {
            guard let signature = entry["signature"] as? String,
                  let frames = entry["frames"] as? [String: [Double]] else { continue }
            var layout: [CGWindowID: CGRect] = [:]
            for (key, values) in frames {
                guard let id = UInt32(key), values.count == 4 else { continue }
                layout[CGWindowID(id)] = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
            }
            set(layout, for: signature)
        }
    }

    init() {}

    /// Whether layouts saved at `savedBoot` belong to this boot: macOS reuses window ids
    /// after a restart, so older ones would move the wrong windows. The boot time read
    /// back can drift a little, hence the minute's slack; 0 means it couldn't be read.
    static func isSameBoot(saved savedBoot: TimeInterval, now: TimeInterval) -> Bool {
        savedBoot > 0 && now > 0 && abs(savedBoot - now) < 60
    }
}
