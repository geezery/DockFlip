# Plinth — Scope

> Working name. Plinth is a free, open-source (GPL-3.0) macOS app that brings the
> Windows 11 taskbar, Alt-Tab window switching and basic window snapping to the Mac —
> alongside the Dock, not instead of it.

## Why

On macOS, the things a Windows user does a hundred times a day are spread across
several apps (a dock-preview app, an Alt-Tab clone, a window manager), each with its
own settings, permissions and quirks — and none of them behaves like Windows out of
the box. Plinth does that one job in one small app that is right with default
settings.

## Guiding principles

1. **Windows 11 default behaviour is the spec.** When in doubt, do what a fresh
   Windows 11 install does. We do not improve on it, extend it, or make it
   configurable. "Should this be a setting?" — default answer: no.
2. **Zero configuration.** A new user installs, grants one permission, and is done.
3. **Reliability before features.** A feature that misbehaves in edge cases
   (Electron apps, dialogs, sleep/wake, display changes) is worse than no feature.
4. **Lightweight.** No third-party dependencies. Event-driven, no polling — with one
   documented exception: Dock badges are read every 15 seconds, because macOS
   offers no notification for them.
5. **Private by default.** Full functionality with Accessibility permission only.
   Screen Recording is opt-in, used only for previews. No networking code at all.
6. **Latest macOS only.** macOS 26 or later. No back-porting.
7. **Free and open.** GPL-3.0, installed with Homebrew.

## Performance budgets (enforced in CI where measurable)

| Metric | Budget |
|---|---|
| CPU at idle | 0 % (no timers running while nothing changes) |
| Memory (resident) | < 50 MB |
| Launch to usable | < 0.5 s |
| ⌘Tab: key press to switcher visible | < 50 ms |

## In scope (v1)

### Dock mode (default)
- The macOS Dock stays as it is: folders, Trash, badges, drag and drop, settings.
- Hover an app icon: list of the app's windows (titles), or previews if enabled.
- Click the front app's icon: minimize its window; click again: restore.
  Click another app's icon: its most recent window comes forward.
- Apps without windows on the current Space: the Dock's own behaviour (launch, reopen).
- How: the Dock's accessibility tree reports the hovered icon; a mouse event tap
  takes over clicks only on icons of apps that have windows (DockDoor's approach).

### Plinth taskbar (alternative, Settings → Taskbar)
- One taskbar per display, showing the windows on that display.
- Default: buttons combined per app, icons only (Windows 11 default).
  Single alternative: never combine, titles shown.
- Pinned apps; on first launch, pins are imported from the Dock.
- Only apps with windows are shown, plus pinned apps.
- Click: activate window. Click on the active window: minimize. Click again: restore.
- Middle-click: close window. Right-click: minimize, close, close all windows,
  quit app, pin/unpin.
- Hover: list of the app's windows (titles), or previews if enabled.
- Minimized and hidden (⌘H) windows are listed and restorable.
- Badges (unread counts) read from the Dock's accessibility tree.
- Dragging a file over a button activates that window (Windows behaviour).
- Right end: clock with calendar flyout, and a "show desktop" strip.

### Window switcher (⌘Tab)
- All windows on the current Space, most-recently-used order.
- Hold ⌘, press Tab to advance; ⇧ reverses; Esc cancels; release ⌘ to switch.
- Windows 7 Flip 3D look: windows in a slanted, receding 3D stack; the selected
  window in front.
- Type to filter: typed words narrow the stack to windows whose title, app or
  document contains them (case and accents ignored). While filtering, releasing
  ⌘ does not switch; Return does, Esc clears the filter. Cleared on close.
- Previews if enabled; otherwise a card per window: title bar tinted with the
  app's colour, app icon, document file name, display name, size, mini-map.
- While open, the switcher is the key window (a non-activating panel, made key
  without activating Plinth, as in AltTab and DockDoor); the previous app gets no
  key presses and stays the active app. Esc returns to it.
- Triggered by Carbon `RegisterEventHotKey` (works while another app holds secure
  keyboard input); ⌘ release is seen by a listen-only modifier tap (AltTab's approach).
- Replaces the native ⌘Tab app switcher while Plinth runs (⌘` stays native). ⌘Tab sits where Alt+Tab sits on a PC keyboard, and apps never receive ⌘Tab, so nothing conflicts. Quitting Plinth restores the native switcher.

### Window management (Windows parity only)
- Keyboard snapping: halves, maximize, restore/minimize, quarters by combination,
  move to next display.
- Drag snapping: drag to left/right edge (half), top edge (maximize),
  corners (quarter).
- If macOS's native edge tiling is on, Plinth detects it and offers to turn it off
  (the two conflict).

### Previews (opt-in)
- Offered explicitly as a choice during onboarding — not preselected, not hidden
  in settings.
- When on: captured only on hover and while ⌘Tab is visible, at thumbnail size,
  kept in memory, never written to disk.
- When off: large app icon, window title, and a mini-map of the window's outline
  on its display. Previews are switched on in onboarding or Settings only — no
  reminders in the taskbar.

### Localization
- English only in v1 (strings are ready for translation).

## Keyboard map

Apple keyboards have no Win key. Plinth uses **⌃⌥** as the Win key. (⌘ conflicts
with app shortcuts; Globe combinations belong to macOS's own tiling.)

| Windows | Plinth |
|---|---|
| Alt+Tab | ⌘Tab |
| Win+← / → | ⌃⌥← / → |
| Win+↑ | ⌃⌥↑ (maximize) |
| Win+↓ | ⌃⌥↓ (restore, then minimize) |
| Win+→ then Win+↑ | ⌃⌥→ then ⌃⌥↑ (top-right quarter) |
| Win+Shift+← / → | ⌃⌥⇧← / → (move to other display) |
| Win+1…9 | ⌃⌥1…9 |
| Win+D | ⌃⌥D (show desktop) |
| Win+T | ⌃⌥T (cycle taskbar buttons) |
| Win+E | ⌃⌥E (new Finder window) |

## Settings (maximum five)

1. Launch at login — on
2. Window previews — off until chosen in onboarding
3. Combine taskbar buttons — always / never
4. Show taskbar on all displays — on
5. Keyboard shortcuts — on

Anything else needs a strong case against principle 1.

## Out of scope

- Replacing the Dock (Trash, Dock folders, Launchpad). The Dock stays.
- Rectangle-style extras: thirds, almost-maximize, centering, gaps,
  grow/shrink, cycling sizes.
- Moving other apps' menu bar icons into a tray.
- Progress bars on taskbar buttons (no macOS equivalent of `ITaskbarList3`).
- "Always on top" for other apps' windows (requires disabling SIP).
- Start menu.
- Per-app CPU/memory, cross-display drag.
- Mac App Store distribution (the sandbox forbids the Accessibility API).
- macOS versions older than 26.

### Beyond Windows (deliberate exceptions)
- **Clean Up**: suggests closing windows unused for three days and quitting apps
  left without windows. Suggest-only, never automatic; costs nothing when unused.
- **Debug log export** for troubleshooting; local file only.

### Also Windows 11 defaults, included
- Remember window locations per display setup, restore on reconnect.
- "Not responding" on a hung app's taskbar button.

## Deferred (after v1, still Windows defaults)

- Snap layouts (hover over the green button).
- Snap assist (offer other windows for the remaining half after a snap).
- Jump lists (recent files per app, from Spotlight metadata).
- Windows on other Spaces (requires private SkyLight calls).

## Platform constraints and how we handle them

| Constraint | Handling |
|---|---|
| No AppBar API: an app cannot reserve screen space | Keep the Dock at the bottom and draw the taskbar over it; "fill" and maximize respect the Dock's reserved area. |
| No DWM-style thumbnails: any window image means pixel access | Previews are opt-in behind Screen Recording; full function without it. |
| Window titles via `CGWindowList` need Screen Recording | Read titles via the Accessibility API instead. |
| Accessibility API sees only the current Space | v1 covers the current Space only. |
| TCC permissions are tied to the code signature | Sign every release with the project's own self-signed certificate — a stable identity without an Apple account. Ad-hoc builds would lose permissions on every update. |
| No notarization (no Apple account, by choice) | One-time approval in Privacy & Security on first launch, explained in onboarding. Distributed from our own Homebrew tap; the official `homebrew/cask` requires notarization. |

## Permissions

| Permission | Required | Used for |
|---|---|---|
| Accessibility | Yes | Listing, focusing, moving, minimizing windows; hotkeys |
| Screen Recording | No (opt-in) | Window previews |

## Prior art and licensing

- [Rectangle](https://github.com/rxhanson/Rectangle) (MIT) — window geometry.
  MIT code may be reused under GPL-3.0 with its copyright notice kept.
- [AltTab](https://github.com/lwouis/alt-tab-macos) (GPL-3.0) — window
  enumeration techniques.
- [DockDoor](https://github.com/ejbills/DockDoor) (GPL-3.0) — dock previews.
