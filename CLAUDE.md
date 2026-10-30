# DockFlip

A free, open-source macOS menu bar app (GPL-3.0) that brings three Windows habits to the Mac:
window lists above Dock icons (with browser tabs), a Flip 3D ⌘Tab that switches *windows*,
and Win-style snapping (⌃⌥ + arrows, drag to edges). It needs only the Accessibility
permission. Swift 6 toolchain, Swift 5 language mode, macOS 26+, Apple frameworks only.

Read before changing behaviour: `SCOPE.md` (what is in and out), `CONTRIBUTING.md` (house
rules), `ARCHITECTURE.md` (how the parts fit), `SECURITY.md` (privacy claims the code must keep).

## Layout

| Path | What |
|---|---|
| `Package.swift` | SwiftPM: library `DockFlipKit`, executable `DockFlip`, test target `DockFlipKitTests`. |
| `Sources/DockFlip/main.swift` | Entry point: `DockFlipApp.run()`. |
| `Sources/DockFlipKit/App/` | Lifecycle (`AppDelegate`), wiring and shortcut routing (`Services`), menu bar menu, settings, onboarding, languages, permission. |
| `Sources/DockFlipKit/Core/` | `WindowRegistry` (all windows, state, MRU order), `WindowServer` (all Spaces), AX helpers, geometry, displays. |
| `Sources/DockFlipKit/Shortcuts/` | Carbon hot keys, the ⌘Tab event taps, turning macOS's own ⌘Tab off. |
| `Sources/DockFlipKit/Switcher/` | ⌘Tab Flip 3D: controller, view, selection and type-to-filter rules. |
| `Sources/DockFlipKit/Dock/` | `DockController`: watches the real Dock (hover, clicks, ⌃⌥1…9). |
| `Sources/DockFlipKit/WindowList/` | The list above a Dock icon: popup, views, browser tab reading. |
| `Sources/DockFlipKit/WindowLayout/` | Snapping (`SnapEngine` rules, `SnapController` input, overlay), Show Desktop, edge tiling switch. |
| `Sources/DockFlipKit/{Previews,Placement,Cleanup,UI,Diagnostics}/` | Opt-in thumbnails; positions per display setup; Clean Up window; shared views; logging. |
| `Tests/DockFlipKitTests/` | Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`) for the pure rules. |
| `Resources/` | `Info.plist` template (`__VERSION__`, `__BUILD__`, `__BUNDLE_ID__`), app icon, 15 `*.lproj/Localizable.strings`. |
| `site/` | Homepage (static HTML, `i18n.js` holds its translations), deployed by `.github/workflows/pages.yml`. |
| `docs/wiki/` | GitHub wiki pages, synced by `.github/workflows/wiki.yml`; `docs/IT.md` for admins. |
| `scripts/` | Signing certificate, release identity, app icon and PPPC profile helpers. |
| `.github/workflows/` | `ci.yml` (build + test on `macos-26`), `release.yml` (on a `v*` tag), `pages.yml`, `wiki.yml`. |

## Commands

DockFlip builds only on macOS 26 with the Command Line Tools (`xcode-select --install`);
Xcode is optional. Run from the repository root:

| Command | What it does |
|---|---|
| `make` / `make app` | `swift build -c release` and assemble `build/DockFlip.app`, signed. |
| `make test` | `swift test --disable-xctest`: the Swift Testing suites. |
| `make run` | Build the app and open it from `build/`. |
| `make install` | Create the local signing certificate (first time), build, install to `/Applications`. |
| `make uninstall` | Quit and remove the app, its permission, settings and certificate. |
| `make clean` | Remove `.build/` and `build/`. |
| `make app VERSION=0.4.0 SWIFT_FLAGS="--arch arm64 --arch x86_64"` | Universal build, as `release.yml` does. |

Known state (GitHub CI run 40022353598 on `main` at `c79a704`, 2026-10-23, `macos-26`):
`make app` takes about 42 s from clean (Swift compile 30 s), `make test` about 24 s
(compile 21 s), the whole CI job about 75 s. All 21 tests in 7 suites pass. The only
warning is `"DockFlip Signing" not found, signed ad-hoc.`, expected on any machine
without `make cert`. Nothing fails on `main`.

### On the Hogherd farm (Windows)

- The farm's machine is Windows: it has no Swift toolchain, so nothing here builds, tests
  or runs locally, and the project has no landing checks in the pen. The only build and
  test is GitHub Actions `ci.yml` on macOS, after a branch is pushed.
- So compile in your head: read the APIs you call, keep the code you change small, and
  check `@MainActor` isolation, `private` access across files and string keys by reading.
- There is no formatter or linter; match the surrounding code by hand.
- `.github/workflows/ci.yml` names what CI checks: build, `make test`, `plutil -lint` of the
  bundle's `Info.plist`, and `codesign --verify`.

## Conventions

- **House rules** (`CONTRIBUTING.md`): no third-party dependencies; no networking code;
  no polling and no repeating timers (react to Accessibility, `NSWorkspace` and input
  events; a one-shot `Task.sleep` debounce is fine); reliability first; window and tab
  titles never go into the log (log app names only, `privacy: .public` only for non-titles).
- **Scope**: every feature answers "is this one of the best bits of Windows?" (`SCOPE.md`).
  No settings for taste (angles, themes, gaps); defaults instead.
- **No SwiftUI macros** (`@State`, `@Observable`, `@Entry`, `#Preview`): the Command Line
  Tools cannot expand them. View state lives in an `ObservableObject` with `@Published`.
- AppKit for windows and panels (non-activating `NSPanel`s; DockFlip never activates
  itself), SwiftUI for what is inside them, hosted in `NSHostingView`.
- UI state is `@MainActor`; C callbacks (AX observers, event taps, Carbon) hop in with
  `MainActor.assumeIsolated`. Work off the main thread hands results back to it.
- A failed Accessibility read is not an answer: keep what was known and ask again later.
- Pure logic (ordering, geometry, selection, filtering) lives in small value types with no
  AppKit, and has tests in `Tests/DockFlipKitTests`. SwiftPM keeps tests in `Tests/`, not
  beside the source: name the test file after the feature it tests.
- Strings: user-facing text is English and the English is the key, `L("…")` in AppKit and
  `Text("…")` in SwiftUI. Add every new string to all 15 `Resources/*.lproj/Localizable.strings`
  (English as a placeholder is fine). The homepage's strings are in `site/i18n.js`.
- New code goes into its feature's folder; shared views go to `UI/`. Comments explain *why*
  (macOS quirks, timing), in plain English; doc comments use `///`.
- Docs stay true: a change to shortcuts, settings or permissions updates `README.md`,
  `docs/wiki/` and, when it shows on the homepage, `site/`.
- PRs follow `.github/PULL_REQUEST_TEMPLATE.md`. A release is a `v*` tag (`RELEASING.md`);
  the app's version comes from the tag, not the Makefile.

## Split things

- Organise the code by feature: a big module is a folder with one file per job, and its tests next to it. Split a file before it grows past about 400 lines instead of letting it grow.
- Cut work into pieces one pig finishes in one session. Finish one piece well, and put the rest in the barn as ideas, each one piece.
- Commit in logical pieces, each with a clear message.
