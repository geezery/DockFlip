# DockFlip — Scope

> DockFlip is a free, open-source (GPL-3.0) macOS app that brings the best bits of
> Windows to the Mac: window lists on the Dock, a Flip 3D window switcher on ⌘Tab and
> window snapping. It works on top of the Dock, not instead of it.

## Why

On macOS, the things a Windows user does a hundred times a day are spread across
several apps (a Dock preview app, an Alt-Tab clone, a window manager). Each has its
own settings, permissions and quirks, and none of them behaves like Windows out of
the box. DockFlip does that one job in one small app that is right with its default
settings.

## Guiding principles

1. **The best bits of Windows, and only those.** A feature gets in when Windows
   users miss it on a Mac the first week and still miss it a month later. Alt+Tab
   that switches windows: in. Snapping: in. The Start menu, Cortana and the
   "restart now?" dialog: no thanks. When Windows versions disagree, take the one
   people remember fondly (Flip 3D from Windows 7, quarter snapping from
   Windows 10). Take the behaviour, not the looks: DockFlip should feel at home
   on a Mac.
2. **No settings for taste.** "Should this be a setting?" Default answer: no. If
   people would argue about it, pick the better answer and ship that.
3. **Zero configuration.** A new user installs, grants one permission, and is done.
4. **Reliability before features.** A feature that misbehaves in edge cases
   (Electron apps, dialogs, sleep/wake, display changes) is worse than no feature.
5. **Lightweight.** No third-party dependencies. Event-driven, no polling, no
   repeating timers.
6. **Private by default.** Full functionality with Accessibility permission only.
   Screen Recording is opt-in, used only for previews. No networking code at all.
7. **Latest macOS only.** macOS 26 or later. No back-porting.
8. **Free and open.** GPL-3.0, installed with Homebrew.

## Performance budgets (enforced in CI where measurable)

| Metric | Budget |
|---|---|
| CPU at idle | 0 % (no timers running while nothing changes) |
| Memory (resident) | < 50 MB |
| Launch to usable | < 0.5 s |
| ⌘Tab: key press to switcher visible | < 50 ms |

## In scope (v1)

### The Dock
- The macOS Dock stays as it is: folders, Trash, badges, drag and drop, settings.
- Hover an app icon: list of the app's windows (titles), or previews if enabled.
- Click the front app's icon: minimize its window; click again: restore.
  Click another app's icon: its most recent window comes forward.
- Apps without windows: no popup; the Dock's own behaviour (launch, reopen).
- Browser tabs (Safari, Chrome, Edge, Firefox, Brave, Vivaldi, Opera; also Finder
  and Terminal tabs) are listed under their window, read from the tab bar through
  Accessibility off the main thread, never from page content. Site chips from the
  title suffix, duplicates marked, more than 8 folded. Windows 7 showed IE tabs on
  the taskbar; Windows 11 shows Edge tabs in Alt+Tab. Tab titles are never logged.
  Firefox turns on its accessibility engine when asked for its tabs.
- How: the Dock's accessibility tree reports the hovered icon; a mouse event tap
  takes over clicks only on icons of apps that have windows (DockDoor's approach).

### Window switcher (⌘Tab)
- All windows, most-recently-used order: the current Space, minimized windows,
  and windows on other Spaces — on a Mac, full-screen apps live in Spaces of
  their own (marked "On another desktop"). Windows that Accessibility does not
  list (other Spaces) are found by AltTab's element-id walk, off the main thread.
- Hold ⌘, press Tab to advance; ⇧ reverses; Esc cancels; release ⌘ to switch.
- Windows 7 Flip 3D look: windows in a slanted, receding 3D stack; the selected
  window in front.
- Type to filter: typed words narrow the stack to windows whose title, app or
  document contains them (case ignored; ä and ö count as letters of their own). While filtering, releasing
  ⌘ does not switch; Return does, Esc clears the filter. Cleared on close.
- Previews if enabled; otherwise a card per window: title bar tinted with the
  app's colour, app icon, document file name, display name, size, mini-map.
- While open, the switcher is the key window (a non-activating panel, made key
  without activating DockFlip, as in AltTab and DockDoor); the previous app gets no
  key presses and stays the active app. Esc returns to it.
- Triggered by Carbon `RegisterEventHotKey` (works while another app holds secure
  keyboard input); ⌘ release is seen by a listen-only modifier tap (AltTab's approach).
- Replaces the native ⌘Tab app switcher while DockFlip runs (⌘` stays native). ⌘Tab sits where Alt+Tab sits on a PC keyboard, and apps never receive ⌘Tab, so nothing conflicts. Quitting DockFlip restores the native switcher.

### Window management (the parts Windows got right)
- Keyboard snapping: halves, maximize, restore/minimize, quarters by combination,
  move to next display.
- Drag snapping: drag to left/right edge (half), top edge (maximize),
  corners (quarter).
- If macOS's native edge tiling is on, DockFlip detects it and offers to turn it off
  (the two conflict).

### Previews (opt-in)
- Offered explicitly as a choice during onboarding — not preselected, not hidden
  in settings.
- When on: captured only on hover and while ⌘Tab is visible, at thumbnail size,
  side by side. The last picture of a window stays in memory for up to two
  minutes (at most 24), so lists open with pictures at once and minimized or
  other-desktop windows still show how they looked. Never written to disk;
  dropped on screen lock and sleep.
- Browsers with previews on: the tab list stays, with one picture of the window
  under the mouse below it.
- When off: large app icon, window title, and a mini-map of the window's outline
  on its display. Previews are switched on in onboarding or Settings only — no
  reminders anywhere else.

### Languages
- 15: English, Finnish, Swedish, Danish, Norwegian, German, French, Spanish,
  Italian, Portuguese (Brazil), Dutch, Polish, Japanese, Korean, Chinese
  (Simplified). Follows macOS; the menu bar menu can pin one for DockFlip only,
  every language shown with its English name so English is always findable.

## Keyboard map

Apple keyboards have no Win key. DockFlip uses **⌃⌥** as the Win key. (⌘ conflicts
with app shortcuts; Globe combinations belong to macOS's own tiling.)

| Windows | DockFlip |
|---|---|
| Alt+Tab | ⌘Tab |
| Win+← / → | ⌃⌥← / → |
| Win+↑ | ⌃⌥↑ (maximize) |
| Win+↓ | ⌃⌥↓ (restore, then minimize) |
| Win+→ then Win+↑ | ⌃⌥→ then ⌃⌥↑ (top-right quarter) |
| Win+Shift+← / → | ⌃⌥⇧← / → (move to other display) |
| Win+1…9 | ⌃⌥1…9 (n-th app in the Dock) |
| Win+D | ⌃⌥D (show desktop) |
| Win+E | ⌃⌥E (new Finder window) |

## Settings (three)

1. Launch at login — on
2. Window thumbnails — off until chosen in onboarding
3. Keyboard shortcuts — on

Anything else needs a strong case against principles 1 and 2.

## Out of scope

- Replacing the Dock. The Dock stays; an own taskbar was built and dropped
  before v1 (it is in the git history).
- Rectangle-style extras: thirds, almost-maximize, centering, gaps,
  grow/shrink, cycling sizes.
- Moving other apps' menu bar icons into a tray.
- Progress bars on Dock icons (no macOS equivalent of `ITaskbarList3`).
- "Always on top" for other apps' windows (requires disabling SIP).
- Start menu.
- Per-app CPU/memory, cross-display drag.
- Mac App Store distribution (the sandbox forbids the Accessibility API).
- macOS versions older than 26.

### Not from Windows, but earned their place
- **Clean Up**: suggests closing windows unused for three days and quitting apps
  left without windows. Suggest-only, never automatic; costs nothing when unused.
- **Debug log export** for troubleshooting; local file only.

### Also from Windows, included
- Remember window locations per display setup, restore on reconnect.
- "Not responding" on a hung app's window list.

## Deferred (after v1)

- Snap layouts (hover over the green button).
- Snap assist (offer other windows for the remaining half after a snap).
- Jump lists (recent files per app, from Spotlight metadata).

## Platform constraints and how we handle them

| Constraint | Handling |
|---|---|
| No API to extend the Dock | Watch the Dock's Accessibility tree for the hovered icon; take over clicks with a mouse event tap only on icons of apps with windows. |
| No DWM-style thumbnails: any window image means pixel access | Previews are opt-in behind Screen Recording; full function without it. |
| Window titles via `CGWindowList` need Screen Recording | Read titles via the Accessibility API instead. |
| Accessibility API sees only the current Space | The window server lists all Spaces; their windows are reached with AltTab's element-id walk. |
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
