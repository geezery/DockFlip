import AppKit

/// Entry point. DockFlip runs as an accessory app: no Dock icon, a menu bar item only.
public enum DockFlipApp {
    public static func run() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            withExtendedLifetime(delegate) {
                app.run()
            }
        }
    }
}
