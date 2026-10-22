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

    /// What a read saw, for the debug log when no tabs were found (role names
    /// and counts only — never titles).
    struct ReadStats: Sendable {
        var visited = 0
        var tabGroups = 0
        var tabButtons = 0
        var untitledTabs = 0
        var roles: [String: Int] = [:]

        var summary: String {
            let top = roles.sorted { $0.value > $1.value }.prefix(14).map { "\($0.key)×\($0.value)" }
            return "visited \(visited), tab groups \(tabGroups), tab buttons \(tabButtons), untitled \(untitledTabs); " + top.joined(separator: " ")
        }
    }

    /// Reads the tabs of `window`: every tab button inside its tab bar, however
    /// deeply the browser nests it (Safari puts its tabs a few groups down inside
    /// the toolbar). Breadth-first, never into web pages, with a node limit.
    /// Thread-safe: call it off the main thread.
    static func read(window: AXUIElement, windowID: CGWindowID) -> (tabs: [BrowserTab], stats: ReadStats) {
        var stats = ReadStats()
        var queue: [(element: AXUIElement, depth: Int, inTabBar: Bool)] = [(window, 0, false)]
        var head = 0
        var found: [(element: AXUIElement, position: CGPoint)] = []
        var pendingInTabBar = 0
        while head < queue.count, stats.visited < 1500 {
            let (element, depth, inTabBar) = queue[head]
            head += 1
            if inTabBar { pendingInTabBar -= 1 }
            // Tabs found and nothing of a tab bar left to look at: done.
            if !found.isEmpty, pendingInTabBar <= 0, !inTabBar { break }
            stats.visited += 1
            let role = element.string(kAXRoleAttribute) ?? "?"
            stats.roles[role, default: 0] += 1
            if role == "AXWebArea" { continue } // page content: never inside
            let subrole = element.string(kAXSubroleAttribute)
            if subrole == "AXTabButton" || (inTabBar && role == kAXRadioButtonRole) {
                found.append((element, element.frame?.origin ?? .zero))
                continue
            }
            let isTabBar = role == kAXTabGroupRole
            if isTabBar { stats.tabGroups += 1 }
            guard depth < 14 else { continue }
            for child in element.elements(kAXChildrenAttribute) {
                let childInTabBar = inTabBar || isTabBar
                if childInTabBar { pendingInTabBar += 1 }
                queue.append((child, depth + 1, childInTabBar))
            }
        }
        // Breadth-first order is not tab order when pinned tabs sit in a group of
        // their own: sort by place on screen (left to right, then top to bottom).
        found.sort { $0.position.x != $1.position.x ? $0.position.x < $1.position.x : $0.position.y < $1.position.y }
        let vertical = found.count > 1 && Set(found.map(\.position.x)).count == 1
        if vertical { found.sort { $0.position.y < $1.position.y } }

        stats.tabButtons = found.count
        var tabs: [BrowserTab] = []
        for (element, _) in found {
            let fullTitle = title(of: element)
            guard !fullTitle.isEmpty else {
                stats.untitledTabs += 1
                continue
            }
            let parts = TabTitle.split(fullTitle)
            // A tab is a radio button: its value is 1 when it is the selected tab.
            let selected = (element.copyAttribute(kAXValueAttribute) as? NSNumber)?.boolValue ?? false
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
        return (tabs, stats)
    }

    /// A tab's title: its own title or description, or else the text inside it.
    private static func title(of element: AXUIElement) -> String {
        for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
            if let text = element.string(name)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        var level = element.elements(kAXChildrenAttribute)
        for _ in 0..<2 {
            for child in level where child.string(kAXRoleAttribute) == kAXStaticTextRole {
                if let text = child.string(kAXValueAttribute)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                    return text
                }
            }
            level = level.flatMap { $0.elements(kAXChildrenAttribute) }
        }
        return ""
    }

    /// Selects the tab. The caller then brings its window forward.
    static func select(_ tab: BrowserTab) {
        tab.element.perform(kAXPressAction)
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
                let read = BrowserTabs.read(window: job.element.element, windowID: job.id)
                if read.tabs.isEmpty {
                    // A window with one tab has no tab bar (common, kept out of the log
                    // unless debug logging is on); a tab bar without tabs is worth a look.
                    let summary = read.stats.summary
                    if read.stats.tabGroups > 0 {
                        Log.registry.notice("No tabs found in window \(job.id, privacy: .public): \(summary, privacy: .public)")
                    } else {
                        Log.registry.debug("No tab bar in window \(job.id, privacy: .public): \(summary, privacy: .public)")
                    }
                }
                results.append((job.id, read.tabs))
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
                Log.registry.notice("Read \(total, privacy: .public) tabs in \(finished.count, privacy: .public) windows")
                done()
            }
        }
    }
}
