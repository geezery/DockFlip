# Plinth

The Windows 11 taskbar, Alt-Tab and window snapping for macOS — in one small,
free, open-source app that works with default settings.

> **Status:** early development (milestone M1: window core and ⌘Tab).
> See [SCOPE.md](SCOPE.md) and [ROADMAP.md](ROADMAP.md).

## What works today

- **⌘Tab** switches between all windows on the current Space in most-recently-used
  order, including minimized windows and windows of hidden apps.
  Hold ⌘ and press Tab to move forward, ⇧ to go back, Esc to cancel, release ⌘ to
  switch. ← → and Return work too; you can also click a window.
- Each window shows its app icon, its title and a **mini-map** of where the window
  sits on its display — no Screen Recording permission needed.
- First-run setup for the Accessibility permission. Menu bar item with
  "Launch at Login" and "Quit".

Next: the taskbar (M2), then snapping (M3).

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

1. **Creates a local code-signing certificate** ("Plinth Local Signing") in your
   login keychain — first time only. macOS asks for your login password once.
   This keeps the Accessibility permission valid across rebuilds; without it,
   macOS would forget the permission every time the app changes.
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

macOS can keep a stale Accessibility entry. Remove Plinth from the Accessibility
list with the – button, start Plinth again and allow it once more.

## Privacy

- **One permission:** Accessibility, used to list, focus, move and minimize
  windows and for keyboard shortcuts.
- Window titles are read through Accessibility, not through screen capture.
- **No networking code** and no third-party dependencies.
- Window previews (later milestone) will be opt-in and are the only feature that
  will ever use Screen Recording.

## Project layout

```
Sources/Plinth/          executable entry point
Sources/PlinthKit/App/       app delegate, onboarding, permissions
Sources/PlinthKit/Core/      window registry (Accessibility + window server), geometry
Sources/PlinthKit/Switcher/  ⌘Tab: event tap, selection, panel and view
Tests/PlinthKitTests/    unit tests (Swift Testing)
Resources/               Info.plist, localizations (en, fi)
scripts/                 local signing certificate
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The guiding rule: Windows 11 default
behaviour is the spec — see [SCOPE.md](SCOPE.md).

## License

GPL-3.0. See [LICENSE](LICENSE).
