# Features

## 🪟 Window lists in the Dock

<img src="https://github.com/geezery/DockFlip/raw/main/docs/assets/feature-dock.gif" alt="Dock window list" width="100%">

Rest the mouse on an app in the Dock, and its windows pop up in a list above it.

- **The active window is marked** with an accent bar and the words "Active
  window", so you don't have to rely on bold text alone.
- **Click a window** to go to it. **Press ×** to close it.
- **Minimized windows** and **windows on other desktops** are listed too, and
  say so.
- **Click the app you're in** to minimize its window, and click again to bring
  it back. Clicking another app brings its most recent window forward. Clicks
  with modifier keys (⌘, ⌥ and so on) go to the Dock as usual.
- **Apps without windows** get no list; the Dock does what it always does.
- **The Dock is untouched.** Folders, Trash, badges, drag and drop, magnification
  and your Dock position (bottom, left or right) all work as before.

### Browser tabs

Safari, Chrome, Edge, Firefox, Brave, Vivaldi and Opera list each window's tabs
under it, and so do Finder and Terminal.

- The tab you're on is marked in the app's colour.
- Each site gets its own colour chip, and the same site always gets the same colour.
- Duplicate tabs are marked "Duplicate", for the 14 tabs of the same doc we all
  have open.
- Long lists fold after eight tabs; "Show all N tabs" unfolds them.
- Click a tab to go straight to it.

Tabs are read from the browser's tab bar, never from page content.

### Thumbnails (optional)

With thumbnails on, apps with up to five windows show picture cards. Browsers
and apps with more windows keep the list, with one big picture of the window
under the mouse.

## 🃏 ⌘Tab, Flip 3D edition

<img src="https://github.com/geezery/DockFlip/raw/main/docs/assets/feature-flip.gif" alt="Flip 3D window switcher" width="100%">

Hold ⌘ and press Tab: every window stands in a slanted 3D stack, with the most
recently used in front.

| Key | Action |
|---|---|
| Tab | Next window |
| ⇧ Tab | Previous window |
| ← → | Move through the stack |
| Release ⌘ | Switch to the window in front |
| Return | Switch (also while filtering) |
| Esc | Cancel, or clear the filter |
| Click | Switch to that window |

- **Type to filter.** While holding ⌘, type part of a window's title, app name
  or document name. The stack narrows as you type, and Return switches.
  Matching ignores case, but ä and ö count as letters of their own, so "öö"
  won't find "Outlook".
- **Every window:** minimized ones, full-screen apps and windows on other
  desktops.
- **Without thumbnails** each window is a card showing the title in a bar of the
  app's colour, the app icon, the document name, the display it's on, its size
  and a mini-map.
- **With thumbnails** the window's own close, minimize and zoom buttons are
  covered by the app's icon, because forty identical traffic lights aren't
  helping anyone.
- **Works under secure input.** Password fields and some terminal modes turn on
  macOS's secure keyboard input, which blinds most switchers. DockFlip's keeps
  working.

macOS's own ⌘Tab is switched off while DockFlip runs and comes back when you
quit. ⌘` stays the macOS way.

## 📐 Snapping

<img src="https://github.com/geezery/DockFlip/raw/main/docs/assets/feature-snap.gif" alt="Window snapping" width="100%">

**⌃⌥ plays the Win key.** See [[Keyboard Shortcuts]] for the full map.

- **Keyboard:** halves, maximize, restore and minimize, quarters, and moving a
  window to the next display.
- **Mouse:** drag a window to the left or right edge for a half, to the top
  edge to maximize, or near a corner for a quarter. A preview shows where it
  will land.

## 🧹 The small stuff

- **Windows remember their place for each display setup.** Unplug the external
  display, plug it back in, and every window returns to where it was.
- **Clean Up** (menu bar → *Clean Up…*) lists windows unused for three days and
  apps running without windows. It only suggests. Nothing closes without you,
  and apps still ask to save.
- **Not responding:** a hung app's window list says so.
- **Show desktop** with ⌃⌥D, like Win+D.
- **Window Layout** in the menu bar menu lists every shortcut; clicking one
  applies it.

## What DockFlip deliberately doesn't do

- Replace the Dock. (We built our own taskbar once. The real Dock won.)
- Thirds, gaps, "almost maximize" and other Rectangle-style extras. Rectangle
  does those beautifully.
- A Start menu. Spotlight is right there.
- Settings for things that should just work.
