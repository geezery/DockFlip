import AppKit
import ApplicationServices

/// What the window server knows about windows, independent of Accessibility.
///
/// Accessibility (`WindowRegistry`) gives titles and actions but only lists the
/// windows on the current Space; the window server lists every window of every
/// app on every Space, with no titles. DockFlip uses both: this file is the one
/// place that reads the window server.
enum WindowServer {
    struct Entry {
        let id: CGWindowID
        let pid: pid_t
        /// AX space (top-left origin).
        let bounds: CGRect
    }

    /// Normal-layer windows, front to back.
    /// - onScreenOnly: only those on the current Space and not minimized.
    /// - visibleOnly: leave out fully transparent windows. Off for bookkeeping —
    ///   a window fading in or out still exists.
    static func windows(onScreenOnly: Bool, visibleOnly: Bool = false) -> [Entry] {
        let options: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let owner = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { return nil }
            if visibleOnly, let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0 { return nil }
            return Entry(id: CGWindowID(number.uint32Value), pid: pid_t(owner.int32Value), bounds: bounds)
        }
    }

    /// Ids of the windows on the current Space, front to back.
    static func onScreenIDs() -> [CGWindowID] {
        windows(onScreenOnly: true).map(\.id)
    }

    /// Real windows (not tiny helper windows) of every app on every Space,
    /// minimized ones included, by owner.
    static func inventory(visibleOnly: Bool = false) -> [pid_t: Set<CGWindowID>] {
        var result: [pid_t: Set<CGWindowID>] = [:]
        for entry in windows(onScreenOnly: false, visibleOnly: visibleOnly) where entry.bounds.width >= 100 && entry.bounds.height >= 60 {
            result[entry.pid, default: []].insert(entry.id)
        }
        return result
    }

    /// Finds the Accessibility elements of windows Accessibility does not list
    /// (other Spaces, full-screen apps) by walking the app's element ids with
    /// `_AXUIElementCreateWithRemoteToken` — AltTab's technique. Stops when all
    /// `ids` are found or `budget` seconds have passed. Thread-safe; never call
    /// it on the main thread.
    static func findWindows(pid: pid_t, ids: Set<CGWindowID>, budget: TimeInterval = 0.3) -> [CGWindowID: AXUIElement] {
        // Token layout: pid (4 bytes), 0 (4), "coco" (4), element id (8).
        guard let token = CFDataCreateMutable(kCFAllocatorDefault, 20) else { return [:] }
        CFDataSetLength(token, 20)
        guard let bytes = CFDataGetMutableBytePtr(token) else { return [:] }
        memset(bytes, 0, 20)
        var pidField = pid
        memcpy(bytes, &pidField, 4)
        var magic = Int32(0x636f636f)
        memcpy(bytes + 8, &magic, 4)

        var found: [CGWindowID: AXUIElement] = [:]
        let deadline = ProcessInfo.processInfo.systemUptime + budget
        var elementID: UInt64 = 0
        while found.count < ids.count, ProcessInfo.processInfo.systemUptime < deadline {
            memcpy(bytes + 12, &elementID, 8)
            elementID += 1
            guard let element = _AXUIElementCreateWithRemoteToken(token)?.takeRetainedValue(),
                  let windowID = element.windowID, ids.contains(windowID), found[windowID] == nil,
                  // Elements inside a window report the window's id too: keep the window itself.
                  element.string(kAXRoleAttribute) == kAXWindowRole else { continue }
            found[windowID] = element
        }
        return found
    }
}
