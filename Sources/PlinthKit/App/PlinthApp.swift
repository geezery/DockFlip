import AppKit

/// Entry point. Plinth runs as an accessory app: no Dock icon, a menu bar item only.
public enum PlinthApp {
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
