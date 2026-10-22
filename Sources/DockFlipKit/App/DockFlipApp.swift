import AppKit

/// Entry point. DockFlip runs as an accessory app: no Dock icon, a menu bar item only.
public enum DockFlipApp {
    public static func run() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            // `kill`, `pkill`, the installer and logging out end apps with SIGTERM,
            // which skips AppKit's normal quit. Turn it into a normal quit, so
            // macOS's own ⌘Tab is always given back.
            signal(SIGTERM, SIG_IGN)
            let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
            termination.setEventHandler { MainActor.assumeIsolated { NSApp.terminate(nil) } }
            termination.resume()
            withExtendedLifetime((delegate, termination)) {
                app.run()
            }
        }
    }
}
