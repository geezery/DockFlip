# Privacy and Permissions

DockFlip is nosy about your windows and nothing else.

## Permissions

| Permission | Needed? | Used for |
|---|---|---|
| Accessibility | **Yes** | Listing, focusing, moving and minimizing windows; reading browser tab titles; the keyboard shortcuts |
| Screen Recording | **No, opt-in** | Window thumbnails, and nothing else |

## What DockFlip never does

- **No networking code.** None. No analytics, no crash reporter, no update
  check. There's no code that could send anything anywhere, which you can
  check with a quick search of the source.
- **No third-party code.** Apple frameworks only.
- **No window or tab titles in the debug log.** The log records timings and
  counts, not what you were looking at.
- **No page content.** Browser tabs are read from the tab bar only.

## Thumbnails, in detail

If you turn thumbnails on:

- Pictures are taken **on demand**: when you hover a Dock icon or open ⌘Tab.
- They're taken **at thumbnail size**, one window at a time.
- They're kept **in memory only**: at most 24 pictures, for up to two minutes,
  and dropped when the screen locks or the Mac sleeps. They're never written
  to disk.
- They're **never** taken while a password field is active.
- **Password managers and System Settings are never pictured.** Their windows
  show a card with a lock instead.

All of this lives in one file, `Sources/DockFlipKit/Previews/PreviewProvider.swift`,
so you can read every rule yourself.
