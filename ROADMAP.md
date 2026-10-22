# DockFlip — Roadmap

Each milestone ends in a build that is usable on its own. A milestone is done when
its exit criteria hold on a clean macOS 26 install with default settings.

## M0 — Foundations
- Repository, GPL-3.0, README, SCOPE, ROADMAP, CONTRIBUTING.
- Swift Package + Makefile that assembles the `.app` bundle. Builds with the
  Command Line Tools only — no Xcode project, no Apple account.
- GitHub Actions on `macos-26`: build, unit tests, launch-time and memory check.
- Onboarding: Accessibility permission flow; previews choice.

**Exit:** CI green on every push; the app launches, asks for Accessibility, and
shows a menu bar icon.

## M1 — Window core and ⌘Tab
- `WindowRegistry`: windows from `CGWindowListCopyWindowInfo` + Accessibility API;
  `AXObserver` per app; `NSWorkspace` notifications; MRU history.
- Only `AXStandardWindow` subrole; panels, sheets and dialogs ignored.
- Reconcile after wake and display changes.
- ⌘Tab switcher: icon + title + window mini-map.

**Exit:** ⌘Tab switches correctly between 30+ windows across Finder, Safari,
Chrome, VS Code, Slack (Electron), Terminal and Xcode, through sleep/wake and
monitor plug/unplug, for a week of daily use without a wrong switch.

## M2 — Taskbar (done, then replaced)
- An own taskbar drawn over the Dock area. Built and tested; dropped in favour of
  the Dock itself (M3.6). Kept in the git history.

## M3 — Window management
- ⌃⌥ keyboard snapping per the keyboard map.
- Drag snapping to edges and corners, with a snap preview overlay.
- Native edge tiling detection and an offer to turn it off.

**Exit:** the listed gestures snap the way a Windows user expects, on one display
and on two.

## M3.5 — Daily-use extras
- Clean Up window (usage tracking, memory per app, keep list).
- Window positions remembered per display setup.
- "Not responding" indicator.
- Debug logging, timing statistics and debug log export.

## M3.6 — The Dock and Flip 3D (v0.3)
- Hover window lists and click-to-minimize on the real Dock; the own taskbar removed.
- ⌘Tab as Windows 7 Flip 3D, with type-to-filter; holds the keyboard while open.
- Carbon hot keys for all shortcuts (work under secure keyboard input).
- Windows on other Spaces and full-screen apps.
- Window cards that tell windows apart without thumbnails.
- Browser tabs in the Dock window list.
- Window Layout cheat sheet in the menu bar menu.
- 15 languages with a language menu.
- Code review: feature folders, shared helpers, ARCHITECTURE.md; renamed to DockFlip.

## M4 — Previews and polish
- Opt-in previews with ScreenCaptureKit; capture on demand, memory only.
- Performance budgets verified.

## M5 — Release (v1.0) — no Apple account, no fees
- Releases are signed in CI with the project's own self-signed code-signing
  certificate (private key in GitHub Secrets). The signing identity stays the same
  across versions, so Accessibility and Screen Recording survive updates.
- Not notarized: macOS asks for a one-time approval in Privacy & Security on first
  launch. Onboarding shows exactly where to click.
- Investigate early: whether Gatekeeper asks again after each update, and how to
  avoid it.
- Homebrew cask in our own tap: `brew install <owner>/tap/dockflip`.
  (The official `homebrew/cask` requires notarization, so it is not an option.)
- `make install` for building from source; on first run the Makefile creates a
  local self-signed certificate so permissions survive rebuilds.
- Build provenance attestations on every release.

## Later
- Snap layouts, snap assist, jump lists.
