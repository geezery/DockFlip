import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import DockFlipKit

/// SCOPE.md's ⌘Tab budget, held with 60 windows: `SwitcherView` hosted the way
/// `SwitcherPanel` hosts it, in a panel ordered in but invisible as during the hold,
/// timed opening and taking one ⌘Tab step. A change that makes the stack draw every
/// window again shows here, not first on a heavy user's Mac. Needs a window server:
/// CI's macOS runner has one, as has any Mac someone is logged in to.
@Suite("SwitcherView timing")
@MainActor
struct SwitcherViewTimingTests {
    /// SCOPE.md: "⌘Tab: key press to switcher visible < 50 ms" (see `budgetIsSCOPEs`).
    static let budgetMs = 50
    /// CI's virtual Mac and the debug build `make test` makes are slower than a
    /// user's Mac (the launch check gives launch 4× there). 3× is still no longer
    /// than the 150 ms hold before the stack is drawn, so it would be ready in time.
    static let ciAllowance = 3
    /// Each timing is the median of this many, so one busy moment on the runner
    /// does not fail the run.
    static let rounds = 5
    /// A MacBook Air's screen, so runs on different displays compare.
    static let screen = CGSize(width: 1440, height: 900)

    /// The first ⌘Tab after launch must not build the panel: launch has built it,
    /// off screen. Needs a window server, as the rest of this suite does.
    @Test func prepareBuildsThePanelOffScreen() {
        let panel = SwitcherPanel(model: SwitcherModel())
        #expect(!panel.isBuilt)

        panel.prepare()
        panel.prepare()

        #expect(panel.isBuilt)
        #expect(!panel.isOnScreen)
    }

    @Test func sixtyWindowsOpenAndStepWithinTheBudget() {
        let stage = Stage(size: Self.screen)
        defer { stage.close() }
        let apps = Self.apps()
        let clock = ContinuousClock()
        let cold = clock.measure { stage.warmUp(Self.items(60, apps: apps, firstID: 1)) }

        var opens: [Duration] = []
        var steps: [Duration] = []
        var sixties: [Duration] = []
        var tens: [Duration] = []
        // 60 and 10 windows in turns, so a busy moment on the runner hits both alike.
        // Other windows each time, so every card is built anew, not reused.
        for round in 1...Self.rounds {
            let sixtyItems = Self.items(60, apps: apps, firstID: CGWindowID(round * 1000))
            let tenItems = Self.items(10, apps: apps, firstID: CGWindowID(round * 1000 + 500))
            let opened = clock.measure { stage.open(sixtyItems) }
            let stepped = clock.measure { stage.step() }
            let tenTook = clock.measure { stage.open(tenItems); stage.step() }
            opens.append(opened)
            steps.append(stepped)
            sixties.append(opened + stepped)
            tens.append(tenTook)
        }
        let opening = Self.median(opens)
        let stepping = Self.median(steps)
        let sixty = Self.median(sixties)
        let ten = Self.median(tens)
        let limit = Duration.milliseconds(Self.budgetMs * Self.ciAllowance)
        print("SwitcherView timing: 60 windows, open \(Self.ms(opening)) ms, step \(Self.ms(stepping)) ms "
              + "(limit \(Self.ms(limit)) ms, SCOPE's \(Self.budgetMs) ms × \(Self.ciAllowance)); "
              + "open and step with 10 windows \(Self.ms(ten)) ms, with 60 \(Self.ms(sixty)) ms; "
              + "medians of \(Self.rounds); first open in a process \(Self.ms(cold)) ms, not held to it")

        // Building ten new cards takes milliseconds. Near nothing means SwiftUI drew
        // nothing in `Stage.render`, and then this test times nothing.
        let drawing: Duration = .milliseconds(1)
        #expect(opening > drawing, "Opening took \(Self.ms(opening)) ms: nothing was drawn, so nothing was timed")
        #expect(opening < limit, "Opening ⌘Tab with 60 windows took \(Self.ms(opening)) ms, over \(Self.ms(limit)) ms")
        #expect(stepping < limit, "A ⌘Tab step with 60 windows took \(Self.ms(stepping)) ms, over \(Self.ms(limit)) ms")

        // Only the cards near the front are drawn (`SwitcherStack.drawnIndices`): ten
        // with 10 windows and ten with 60. Drawing every card makes 60 cost about six
        // times as much, on any Mac, however slow the runner is that day.
        let allowed: Duration = ten * 2 + .milliseconds(5)
        #expect(sixty < allowed, "60 windows took \(Self.ms(sixty)) ms, 10 took \(Self.ms(ten)) ms: is every card drawn?")
    }

    @Test func budgetIsSCOPEs() throws {
        // #filePath is Tests/DockFlipKitTests/Switcher/SwitcherViewTimingTests.swift.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let scope = try String(contentsOf: root.appendingPathComponent("SCOPE.md"), encoding: .utf8)
        let row = "| ⌘Tab: key press to switcher visible | < \(Self.budgetMs) ms |"
        #expect(scope.contains(row), "SCOPE.md has no '\(row)' row: change the budget in both")
        #expect(scope.contains("SwitcherViewTimingTests"), "SCOPE.md no longer says which test holds ⌘Tab to its budget")
    }
}

extension SwitcherViewTimingTests {
    /// The switcher's view in a panel like `SwitcherPanel`'s, driven the way
    /// `SwitcherController` drives it, each change drawn at once.
    @MainActor
    final class Stage {
        let model: SwitcherModel
        private let panel: NSPanel
        private let hosting: NSView

        init(size: CGSize, style: SwitcherStyle = .flip3D) {
            // AppKit wants its app object before the first window. An accessory app,
            // as DockFlip is, shows windows without a Dock icon.
            NSApplication.shared.setActivationPolicy(.accessory)
            let model = SwitcherModel()
            model.style = style
            let panel = Panels.make(
                level: .popUpMenu,
                behavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            )
            let hosting = FirstMouseHostingView(rootView: SwitcherRootView(model: model))
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.setFrame(CGRect(origin: .zero, size: size), display: false)
            // Ordered in, but invisible and click-through, as the switcher is during
            // its hold: nobody running the tests sees it or clicks into it.
            panel.alphaValue = 0
            panel.ignoresMouseEvents = true
            panel.orderFrontRegardless()
            self.model = model
            self.panel = panel
            self.hosting = hosting
        }

        /// The first render in a process also loads SwiftUI, fonts and symbols. The
        /// app pays that once, on its first ⌘Tab; the timings leave it out.
        func warmUp(_ items: [SwitcherItem]) {
            open(items)
            step()
        }

        /// As `SwitcherController` opens: a new list, the second window in front, not
        /// animated. The list changes without animation too: rounds come milliseconds
        /// apart, and the last round's cards fading out would be timed with this one's.
        func open(_ items: [SwitcherItem]) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.items = items
                model.selection = 1
            }
            render()
        }

        /// A ⌘Tab once the stack is drawn: the next window comes to the front, animated.
        func step() {
            model.selection = (model.selection + 1) % model.items.count
            render()
        }

        func close() {
            panel.orderOut(nil)
        }

        /// What waits for the next turn of the run loop, done now: SwiftUI updates
        /// the view in layout, the layers draw, and the transaction is committed.
        private func render() {
            hosting.needsLayout = true
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
            CATransaction.flush()
        }
    }

    struct AppLook {
        let name: String
        let icon: NSImage
        let tint: Color
    }

    /// Twelve apps with their own icons, so cards differ as on a busy Mac.
    static func apps() -> [AppLook] {
        let names = ["Mail", "Notes", "Calendar", "Messages", "TextEdit", "Preview",
                     "Music", "Photos", "Maps", "Reminders", "FaceTime", "System Settings"]
        let tints: [Color] = [.blue, .yellow, .red, .green, .gray, .teal, .pink, .orange, .mint, .indigo, .cyan, .purple]
        return names.indices.map { (index: Int) -> AppLook in
            // An app that is not there gets the generic app icon, which draws the same way.
            let icon = NSWorkspace.shared.icon(forFile: "/System/Applications/\(names[index]).app")
            return AppLook(name: names[index], icon: icon, tint: tints[index])
        }
    }

    /// `count` windows of those apps, numbered from `firstID`: long titles, documents,
    /// minimized windows and windows on other desktops among them. No thumbnails, as
    /// with previews off, the default.
    static func items(_ count: Int, apps: [AppLook], firstID: CGWindowID) -> [SwitcherItem] {
        (0..<count).map { (n: Int) -> SwitcherItem in
            let app = apps[n % apps.count]
            let width = 800 + 40 * (n % 9)
            let height = 500 + 30 * (n % 7)
            return SwitcherItem(
                windowID: firstID + CGWindowID(n),
                title: "\(app.name) \(n + 1): a window title long enough to be cut short on its card",
                appName: app.name,
                icon: app.icon,
                minimap: CGRect(x: 0.05 * Double(n % 6), y: 0.04 * Double(n % 5), width: 0.5, height: 0.6),
                isMinimized: n % 11 == 5,
                isOnOtherSpace: n % 13 == 7,
                document: n % 3 == 0 ? "Quarterly report \(n + 1).pages" : nil,
                screenName: "Built-in Retina Display",
                sizeText: "\(width) × \(height)",
                windowSize: CGSize(width: width, height: height),
                tint: app.tint,
                neverPictured: false
            )
        }
    }

    static func median(_ samples: [Duration]) -> Duration {
        samples.sorted()[samples.count / 2]
    }

    /// "12.3"
    static func ms(_ duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        return String(format: "%.1f", Double(seconds) * 1000 + Double(attoseconds) / 1e15)
    }
}
