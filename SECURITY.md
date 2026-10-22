# Security and privacy

DockFlip sits next to every window you open, so it should earn that spot. Here's
exactly what it can see, what it does with it, and how to check all of it
yourself.

## The short version

- **One permission: Accessibility.** That's the whole list.
- **No Screen Recording.** Most Dock preview apps and window switchers ask for it
  on first launch, because they're built around screenshots of your windows.
  DockFlip is built around what macOS already tells it: titles, positions, app
  icons and tabs. Window cards and mini-maps drawn from those look good on their
  own, so DockFlip never needs to see your screen. Real thumbnails exist, but
  they're opt-in and off until you choose them.
- **No networking code.** No analytics, no crash reporter, no update check, no
  licence server. DockFlip can't phone home, and nothing can phone it.
- **No third-party code.** Apple frameworks only, so there's no dependency that
  could slip something in.
- **Titles never reach the log.** The debug log records timings and counts,
  never window or tab titles.

## What Accessibility is used for

| DockFlip reads or does | So that |
|---|---|
| The list of windows, their titles, positions and states | The Dock lists and ⌘Tab can show them |
| Focus, move, resize, minimize and close windows, when you ask | Switching, snapping and Clean Up work |
| Browser tab titles, from the tab bar only, never page content | Tabs show under their window |
| The Dock's hovered icon | The window list opens above the right app |
| Modifier keys (⌘, ⌃, ⌥, ⇧) | It notices when you let go of ⌘ |
| Other keys, **only while the ⌘Tab switcher is open** | Type-to-filter works |

The rest of the time DockFlip doesn't see what you type. Its shortcuts are
registered as system hot keys, so macOS only tells DockFlip when one of them is
pressed.

## If you turn on thumbnails

Thumbnails are the only feature that uses Screen Recording, and they come with
rules:

- Pictures are taken on demand, when you hover a Dock icon or open ⌘Tab, one
  window at a time and at thumbnail size.
- They're kept in memory only: at most 24, for up to two minutes. They're never
  written to disk and are dropped when the screen locks or the Mac sleeps.
- They're never taken while a password field is active.
- Password managers and System Settings are never pictured.

Every rule is in one file:
[`Sources/DockFlipKit/Previews/PreviewProvider.swift`](Sources/DockFlipKit/Previews/PreviewProvider.swift).

## Check it yourself

**No networking.** Search the source; nothing turns up:

```sh
grep -rnE "URLSession|NWConnection|CFNetwork|URLRequest|socket\(" Sources
```

Or watch it with a firewall such as Little Snitch, or `nettop -p DockFlip`.

**The download is the code.** Every release is built by GitHub Actions from the
tagged source, and the disk image comes with a build-provenance attestation and
a SHA-256 checksum:

```sh
gh attestation verify DockFlip-<version>.dmg --repo geezery/DockFlip
shasum -a 256 DockFlip-<version>.dmg
```

**The signature.** Every release is signed with the same identity, which is why
your Accessibility permission survives updates:

```sh
codesign -dv --verbose=2 /Applications/DockFlip.app   # Authority=DockFlip Release
```

## About the warning on first launch

macOS shows a warning the first time you open DockFlip: "Apple could not verify
'DockFlip' is free of malware". That isn't a finding, it's paperwork. Apple only
skips the warning for apps from developers who pay 99 € a year for
notarization, and DockFlip is free.

☕ **That's what the coffee is for.** Once a handful of $2 coffees (or a few bigger cups) cover the
fee, DockFlip gets notarized: download, drag to Applications, open, done. No
warning, no trip to System Settings, and updates that simply open.
[Buy DockFlip a coffee](https://github.com/sponsors/geezery?frequency=one-time).

## Supported versions

Only the latest release gets fixes. DockFlip updates are free, so there's no
reason to stay behind.

## Reporting a vulnerability

If you find a way DockFlip could leak window contents, titles or keystrokes, or
be abused by another app, please report it privately through
[GitHub's private vulnerability reporting](https://github.com/geezery/DockFlip/security/advisories/new)
and not in a public issue. You'll get an answer within a few days, and credit in
the release notes if you'd like it.
