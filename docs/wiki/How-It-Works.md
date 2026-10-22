# How It Works

A tour for the curious. The full map for contributors is
[ARCHITECTURE.md](https://github.com/geezery/DockFlip/blob/main/ARCHITECTURE.md).

## One registry, many features

```
   Accessibility ─┐   ┌─ window server
   NSWorkspace ───┤   │
                  ▼   ▼
              WindowRegistry   ← every feature reads windows here
                  │
   Dock · Switcher · Snapping · Placement · Clean Up · Previews
```

`WindowRegistry` knows every window, its state and the most-recently-used
order. Every feature reads from it and acts through it.

## Event-driven, all the way down

DockFlip never polls. It listens:

- **Accessibility notifications** for windows opening, closing, moving and
  changing title.
- **NSWorkspace notifications** for apps launching, quitting and activating.
- **The Dock's own Accessibility tree**, which reports the hovered icon. A
  mouse-move monitor exists only while the pointer is on the Dock or the list,
  to notice it leaving.
- **Carbon hot keys** for shortcuts. They keep working under secure keyboard
  input, and an event tap that only listens notices ⌘ being released.

## Seeing windows on other desktops

Accessibility only lists windows on the current desktop. The window server knows
about all of them, and DockFlip reaches them with the element-id walk AltTab
worked out. That work runs off the main thread.

## A failed read is not an answer

Slow apps time out. When that happens, DockFlip keeps what it knew and asks
again, rather than deciding the app has no windows.

## Never stealing focus

DockFlip's panels never activate DockFlip. The ⌘Tab panel becomes the key window
without activating the app, so the app you were in stays active, and its
secure keyboard input doesn't block the switcher.

## Built without Xcode

DockFlip is a plain Swift package with a Makefile that assembles the `.app`. It
uses no SwiftUI macros, because their implementations ship only with full
Xcode, so the Command Line Tools are enough.

## Credits

The hard parts of macOS window wrangling were worked out by
[AltTab](https://github.com/lwouis/alt-tab-macos),
[DockDoor](https://github.com/ejbills/DockDoor) and
[Rectangle](https://github.com/rxhanson/Rectangle). DockFlip is GPL-3.0 partly
because it learned from them.
