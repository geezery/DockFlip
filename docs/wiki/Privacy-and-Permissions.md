# Privacy and Permissions

<img src="https://github.com/geezery/DockFlip/raw/main/docs/assets/feature-privacy.gif" alt="What DockFlip asks for" width="100%">

DockFlip is nosy about your windows and nothing else.

## No screen recording required

Most Dock preview apps and window switchers ask for Screen Recording on first
launch, because they're built around screenshots. DockFlip draws its window
cards, mini-maps and tab lists from what macOS already shares through
Accessibility: titles, positions, icons and tabs. It looks polished from the
first second without ever seeing your screen. Thumbnails exist, but they're
opt-in.

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

## Check it yourself

[SECURITY.md](https://github.com/geezery/DockFlip/blob/main/SECURITY.md) shows
how to confirm there's no networking code, verify a download's build provenance
and check its signature.
