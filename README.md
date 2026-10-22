# Plinth

The Windows 11 taskbar, Alt-Tab and window snapping for macOS — in one small,
free, open-source app that works with default settings.

> **Status:** v0.2 preview — all v1 features in, now being tested.
> See [SCOPE.md](SCOPE.md) and [ROADMAP.md](ROADMAP.md).

## Features

**Taskbar** — one per display, on the space the Dock reserves.
- Buttons combined per app (Windows 11 default) or one per window.
- Click to focus, click the active button to minimize, middle-click to close.
- Hover a button: the app's windows open as a list (title + mini-map of where
  each window is), or as thumbnails if you turned previews on. Click to switch,
  × to close.
- Right-click: the app's windows, New Window, Pin/Unpin, Close, Quit.
- Pinned apps (imported from your Dock on first launch), unread badges,
  drag a file over a button to bring that window forward.
- Your Dock's folders (Downloads …) and the Trash next to the clock: click to
  open, drop files on the Trash to delete them.
- Clock with a calendar, and a "show desktop" strip at the far right.

**⌘Tab** — every window on the current Space in most-recently-used order,
including minimized ones. Hold ⌘ and press Tab, ⇧ to go back, Esc to cancel,
release ⌘ to switch. ← → and Return work too; you can also click.

**Snapping** — ⌃⌥ is the Win key.

| Keys | Action |
|---|---|
| ⌃⌥ ← / → | Left or right half; again to move to the next display |
| ⌃⌥ ↑ | Maximize; from a half, the top quarter |
| ⌃⌥ ↓ | Restore, then minimize; from a half, the bottom quarter |
| ⌃⌥⇧ ← / → | Move the window to the next display |
| ⌃⌥ 1…9 | Activate the n-th taskbar button |
| ⌃⌥ D | Show desktop |
| ⌃⌥ E | New Finder window |

Drag a window to the left or right edge for a half, to the top edge to
maximize, near a corner for a quarter.

**Window thumbnails** (opt-in) — see Privacy.

**Remembers window positions per display setup** (Windows 11 default). Unplug
the external display and plug it back in: every window returns to where it was.

**Clean Up** — menu bar → *Clean Up*: windows unused for three days and apps
left running without windows, with how long since you used them and how much
memory the app holds. Nothing closes without you; apps still ask to save.
*Keep* stops suggesting an app.

**Not responding** — a hung app's taskbar button turns grey and says so.

**Debug log** — menu bar → *Save Debug Log…* writes a text file to the Desktop
with system info, timing statistics of every hot path (slowest call and app
included) and this session's log. Turn on *Debug Logging* for per-call detail.
Window titles are never logged. Nothing is sent anywhere.

## Requirements

- macOS 26 or later
- Command Line Tools: `xcode-select --install`
  (no Xcode project, no Apple account)

## Build and install

```sh
git clone <repo-url> plinth
cd plinth
make install
```

`make install` does three things:

1. **Creates a local code-signing identity** ("Plinth Signing") — first time only —
   in its own keychain (`~/Library/Keychains/plinth-signing.keychain-db`) with a
   random password kept in `~/Library/Application Support/Plinth/`. macOS asks for
   your login password once, to trust the certificate. A stable signature keeps the
   Accessibility permission valid across rebuilds. The login keychain is not used,
   so codesign never asks for a keychain password.
2. Builds `build/Plinth.app` and signs it with that certificate.
3. Copies it to `/Applications` and starts it.

Then allow Plinth under **System Settings → Privacy & Security → Accessibility**.
The setup window opens the right page for you.

Other targets: `make` (build only), `make run`, `make test`, `make clean`.

### ⌘Tab and the native app switcher

While Plinth runs, ⌘Tab opens Plinth's window switcher instead of macOS's app
switcher (⌘\` still cycles windows of the current app). Quitting Plinth gives ⌘Tab
back to macOS. If Plinth ever crashes and the native switcher does not come
back, start and quit Plinth once, or log out and in.

### If ⌘Tab does nothing after a rebuild

macOS can keep a stale Accessibility entry: the switch shows "on" but belongs to
an older signature. Press **Reset Permission** in Plinth's setup, or run
`tccutil reset Accessibility io.github.plinth.Plinth`, then allow Plinth again.

## Privacy

- **One permission:** Accessibility, used to list, focus, move and minimize
  windows and for keyboard shortcuts.
- Window titles are read through Accessibility, not through screen capture.
- **No networking code** and no third-party dependencies.
- **Window thumbnails are opt-in** and are the only feature that uses Screen
  Recording. When on, Plinth captures one window at a time, at thumbnail size,
  only while you hover the taskbar or use ⌘Tab; images stay in memory for a few
  seconds and are dropped when the screen locks. Nothing is captured while a
  password field is active anywhere, and never from password managers, Keychain
  Access or System Settings. All of it lives in
  `Sources/PlinthKit/Previews/PreviewProvider.swift`.
- The only periodic work is reading the Dock's unread badges every 15 seconds.

## Project layout

```
Sources/Plinth/          executable entry point
Sources/PlinthKit/App/       app delegate, onboarding, permissions
Sources/PlinthKit/Core/      window registry (Accessibility + window server), geometry
Sources/PlinthKit/Switcher/  ⌘Tab: event tap, selection, panel and view
Sources/PlinthKit/Taskbar/   taskbar panels, hover popup, calendar, badges
Sources/PlinthKit/Snap/      snapping state machine, keyboard and drag snapping
Sources/PlinthKit/Previews/  opt-in thumbnails and their safety rules
Sources/PlinthKit/Cleanup/   usage tracking and the Clean Up window
Sources/PlinthKit/Placement/ window positions per display setup
Sources/PlinthKit/Diagnostics/ logging, timing statistics, debug log export
Tests/PlinthKitTests/    unit tests (Swift Testing)
Resources/               Info.plist, localizations (en, fi)
scripts/                 local signing certificate, app icon generator
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The guiding rule: Windows 11 default
behaviour is the spec — see [SCOPE.md](SCOPE.md).

## License

GPL-3.0. See [LICENSE](LICENSE).
