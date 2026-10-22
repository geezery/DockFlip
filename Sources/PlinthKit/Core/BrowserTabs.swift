import AppKit
import ApplicationServices

/// One tab of a browser (or Finder/Terminal) window, read through Accessibility.
/// Tab titles are shown to the user only; they are never logged.
struct BrowserTab: Identifiable, @unchecked Sendable {
    /// "windowID:index", unique while the window's tabs stay the same.
    let id: String
    let windowID: CGWindowID
    let index: Int
    /// The page title without the site suffix ("Inbox (3)").
    let title: String
    /// The site, from the title's suffix ("Gmail"), when there is one.
    let site: String?
    /// The full title as the browser shows it.
    let fullTitle: String
    let isSelected: Bool
    /// The tab button; pressing it selects the tab.
    let element: AXUIElement
}

/// Splits page titles into the page and the site. Pure, unit-tested.
public enum TabTitle {
    private static let separators = [" - ", " | ", " — ", " – ", " · ", " • "]

    /// "Inbox (3) - antti@example.com - Gmail" → ("Inbox (3) - antti@example.com", "Gmail").
    /// Only a short last part counts as a site, so "Q3 - plan - draft for the board meeting" stays whole.
    public static func split(_ title: String) -> (page: String, site: String?) {
        var best: Range<String.Index>?
        for separator in separators {
            if let range = title.range(of: separator, options: .backwards),
               best == nil || range.lowerBound > best!.lowerBound {
                best = range
            }
        }
        guard let range = best else { return (title, nil) }
        let page = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let site = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !page.isEmpty, !site.isEmpty, site.count <= 28, site.split(separator: " ").count <= 4 else {
            return (title, nil)
        }
        return (page, site)
    }
}

enum BrowserTabs {
    /// Apps whose windows have tabs worth listing. Office apps are left out on
    /// purpose: their ribbons are tab groups too.
    static let apps: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "com.microsoft.edgemac.Dev",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "com.apple.finder", "com.apple.Terminal"
    ]

    static func hasTabs(_ bundleID: String?) -> Bool {
        bundleID.map { apps.contains($0) } ?? false
    }

    /// Reads the tab bar of `window`. Walks the window's Accessibility tree
    /// breadth-first, never into web pages, with a node limit. Thread-safe:
    /// call it off the main thread.
    static func read(window: AXUIElement, windowID: CGWindowID) -> [BrowserTab] {
        var queue: [(AXUIElement, Int)] = [(window, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 800 {
            let (element, depth) = queue.removeFirst()
            visited += 1
            let role = string(element, kAXRoleAttribute)
            if role == "AXWebArea" { continue } // page content: never inside
            if role == kAXTabGroupRole {
                let tabs = tabButtons(in: element, windowID: windowID)
                if !tabs.isEmpty { return tabs }
            }
            guard depth < 10 else { continue }
            for child in children(element) {
                queue.append((child, depth + 1))
            }
        }
        return []
    }

    private static func tabButtons(in group: AXUIElement, windowID: CGWindowID) -> [BrowserTab] {
        var tabs: [BrowserTab] = []
        // Some browsers wrap the tabs in one more group.
        var candidates = children(group)
        if candidates.count == 1, string(candidates[0], kAXRoleAttribute) == kAXGroupRole {
            candidates = children(candidates[0])
        }
        for element in candidates {
            let role = string(element, kAXRoleAttribute)
            let subrole = string(element, kAXSubroleAttribute)
            guard role == kAXRadioButtonRole || subrole == "AXTabButton" else { continue }
            let raw = string(element, kAXTitleAttribute) ?? string(element, kAXDescriptionAttribute) ?? ""
            let fullTitle = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !fullTitle.isEmpty else { continue }
            let parts = TabTitle.split(fullTitle)
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            let selected = (value as? NSNumber)?.boolValue ?? false
            let index = tabs.count
            tabs.append(BrowserTab(
                id: "\(windowID):\(index)",
                windowID: windowID,
                index: index,
                title: parts.page,
                site: parts.site,
                fullTitle: fullTitle,
                isSelected: selected,
                element: element
            ))
        }
        return tabs
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return (value as? [AXUIElement]) ?? []
    }

    /// Selects the tab. The caller then brings its window forward.
    static func select(_ tab: BrowserTab) {
        AXUIElementPerformAction(tab.element, kAXPressAction as CFString)
    }
}

/// Recently read tabs per window. Reading happens off the main thread; results
/// are kept a few seconds so hovering back and forth does not re-read.
@MainActor
final class TabStore {
    static let shared = TabStore()

    private var cache: [CGWindowID: (time: TimeInterval, tabs: [BrowserTab])] = [:]
    private var reading = Set<CGWindowID>()

    /// Drops a window's tabs, e.g. after selecting one of them.
    func forget(_ windowID: CGWindowID) {
        cache[windowID] = nil
    }

    /// Cached tabs of a window (nil when not read yet).
    func tabs(of windowID: CGWindowID) -> [BrowserTab]? {
        cache[windowID]?.tabs
    }

    /// Reads the tabs of `windows` that were not read in the last `maxAge`
    /// seconds, then calls `done` on the main actor (only if anything was read).
    func load(_ windows: [(id: CGWindowID, element: AXUIElement)], maxAge: TimeInterval = 4, done: @escaping @MainActor @Sendable () -> Void) {
        let now = ProcessInfo.processInfo.systemUptime
        cache = cache.filter { now - $0.value.time < 120 }
        let due = windows.filter { window in
            !reading.contains(window.id) && (cache[window.id].map { now - $0.time >= maxAge } ?? true)
        }
        guard !due.isEmpty else { return }
        due.forEach { reading.insert($0.id) }
        let jobs = due.map { (id: $0.id, element: SendableElement(element: $0.element)) }
        Task.detached(priority: .userInitiated) {
            var results: [(CGWindowID, [BrowserTab])] = []
            for job in jobs {
                results.append((job.id, BrowserTabs.read(window: job.element.element, windowID: job.id)))
            }
            let finished = results
            await MainActor.run {
                let store = TabStore.shared
                let time = ProcessInfo.processInfo.systemUptime
                for (id, tabs) in finished {
                    store.reading.remove(id)
                    store.cache[id] = (time, tabs)
                }
                let total = finished.reduce(0) { $0 + $1.1.count }
                Log.registry.debug("Read \(total, privacy: .public) tabs in \(finished.count, privacy: .public) windows")
                done()
            }
        }
    }
}

/// An Accessibility element handed to a background task (AX calls are thread-safe).
struct SendableElement: @unchecked Sendable {
    let element: AXUIElement
}
