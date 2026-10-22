# DockFlip

Your Mac's Dock with the Windows 11 taskbar's habits, a Windows 7 style Flip 3D
⌘Tab that switches windows instead of apps, and Windows window snapping — in one
small, free, open-source app that works with default settings.

> **Status:** v0.3 preview, being tested before the first release.
> See [SCOPE.md](SCOPE.md), [ROADMAP.md](ROADMAP.md) and [ARCHITECTURE.md](ARCHITECTURE.md).

## Features

**The Dock, Windows style.** The Dock stays exactly as it is — folders, Trash,
badges, drag and drop, your settings — and gains:
- Rest the mouse on an app's icon: its windows open as a list (title and a
  mini-map of where each window is), or as pictures if you turned thumbnails on.
  The active window is marked. Click to switch, × to close.
- Click the icon of the app in front to minimize its window, click again to
  restore it; clicking another app brings its most recent window forward.
- Browsers (Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera), Finder and
  Terminal list each window's tabs under it, with each site in its own colour
  and duplicate tabs marked. Click a tab to go straight to it.

**⌘Tab, Flip 3D.** Every window stands in a slanted 3D stack, most recently used
in front — minimized ones, full-screen apps and windows on other desktops
included. Hold ⌘ and press Tab to flip through, ⇧ to go back, Esc to cancel,
release ⌘ to switch; ← → and Return work too, and you can click a window.
Start typing to filter ("team" leaves the Teams windows); then Return switches.
Without thumbnails each window is a card: its title in a bar of the app's
colour, the app icon, the document's file name, the display and a mini-map.

**Snapping.** ⌃⌥ plays the Win key.

| Keys | Action |
|---|---|
| ⌃⌥ ← / → | Left or right half; again to move on to the next display |
| ⌃⌥ ↑ | Maximize; from a half, the top quarter |
| ⌃⌥ ↓ | Restore, then minimize; from a half, the bottom quarter |
| ⌃⌥⇧ ← / → | Move the window to the next display |
| ⌃⌥ 1…9 | Open the n-th app in the Dock |
| ⌃⌥ D | Show desktop (Win+D) |
| ⌃⌥ E | New Finder window (Win+E) |

Drag a window to the left or right edge for a half, to the top edge to
maximize, near a corner for a quarter. All shortcuts are listed under
**Window Layout** in DockFlip's menu bar menu; click one to apply it.

**Window positions per display setup** (Windows 11 default): unplug the
external display, plug it back in, and every window returns to where it was.

**Clean Up** — menu bar → *Clean Up*: windows unused for three days and apps
left running without windows. Nothing closes without you; apps still ask to save.

**Not responding** — a hung app's window list says so.

**15 languages** — English, Finnish, Swedish, Danish, Norwegian, German, French,
Spanish, Italian, Portuguese (Brazil), Dutch, Polish, Japanese, Korean and
Chinese (Simplified). DockFlip follows macOS; the menu bar menu → 🌐 *Language*
picks another one for DockFlip only. Every language is listed with its English
name, and the menu always says "Language" in English too, so English is easy
to find again.

## Requirements

- macOS 26 or later
- Command Line Tools: `xcode-select --install` (no Xcode, no Apple account)

## Build and install

```sh
git clone <repo-url> dockflip
cd dockflip
make install
```

`make install`:

1. Creates a local code-signing identity ("DockFlip Signing") the first time, in
   its own keychain (`~/Library/Keychains/dockflip-signing.keychain-db`) with a
   random password kept in `~/Library/Application Support/DockFlip/`. macOS asks
   for your login password once, to trust the certificate. A stable signature
   keeps the Accessibility permission valid across rebuilds.
2. Builds `build/DockFlip.app` and signs it.
3. Copies it to `/Applications` and starts it.

Then allow DockFlip under **System Settings → Privacy & Security →
Accessibility**; the setup window opens the right page.

Other targets: `make` (build only), `make run`, `make test`, `make clean`.

### Troubleshooting

- **⌘Tab does nothing after a rebuild:** macOS may keep a stale Accessibility
  entry for an older signature. Press **Reset Permission** in setup, or run
  `tccutil reset Accessibility io.github.dockflip.DockFlip`, then allow again.
- **macOS's own ⌘Tab is gone after a crash:** start and quit DockFlip once.
- **A language you cannot read:** menu bar → 🌐 → *English*, or run
  `defaults delete io.github.dockflip.DockFlip AppleLanguages` and restart DockFlip.

## Privacy

- **One permission:** Accessibility, to list, focus, move and minimize windows
  and for the keyboard shortcuts.
- **No networking code**, no third-party code.
- **Thumbnails are opt-in** and the only feature that uses Screen Recording:
  captured on demand (Dock icon hover, ⌘Tab), one window at a time at thumbnail
  size, kept in memory only (at most 24, for two minutes), never while a password
  field is active, never for password managers or System Settings. All of it is in
  `Sources/DockFlipKit/Previews/PreviewProvider.swift`.
- Window and tab titles are never written to the debug log.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [ARCHITECTURE.md](ARCHITECTURE.md).
The guiding rule: Windows 11 default behaviour is the spec ([SCOPE.md](SCOPE.md)).

## License

GPL-3.0. See [LICENSE](LICENSE).
