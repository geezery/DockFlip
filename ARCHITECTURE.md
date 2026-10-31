# How DockFlip works

A map for whoever works on the code next. The code itself says the details;
this says where things are and how they fit.

## The big picture

```
                 macOS
   Accessibility ─┐   ┌─ window server (CGWindowList)
   NSWorkspace ───┤   │
                  ▼   ▼
              WindowRegistry  ◀── every feature reads windows here
                  │                and acts on them through here
   ┌──────────┬───┴──────┬───────────┬────────────┬───────────┐
   ▼          ▼          ▼           ▼            ▼           ▼
 Dock      Switcher   WindowLayout  Placement    Cleanup    Previews
 (hover,   (⌘Tab      (snapping,    (positions   (unused    (opt-in
  clicks)   Flip 3D)   show desktop) per display) windows)   pictures)
   │
   ▼
 WindowList (the list above a Dock icon, with browser tabs)

 Shortcuts ──▶ Services.perform ──▶ the feature the key belongs to
```

Everything runs on the main thread (`@MainActor`), driven by events. Nothing
polls. The few things done off the main thread — reading an app's windows
(`WindowsRead`, on the app's own queue), reading browser tabs, finding windows
on other Spaces, capturing thumbnails — hand their results back to the main
thread.

## Folders (`Sources/DockFlipKit`)

| Folder | What it is |
|---|---|
| `App/` | Lifecycle (`AppDelegate`), feature wiring and shortcut routing (`Services`), the menu bar menu (`StatusMenu`), settings, setup (`Onboarding`), languages, the Accessibility permission. |
| `Core/` | `WindowRegistry` — all windows, their state and most-recently-used order; `WindowServer` — the window server's view (all Spaces); Accessibility helpers; geometry and displays. |
| `Shortcuts/` | `GlobalHotKeys` (Carbon hot keys: ⌘Tab, ⌃⌥…), `SwitcherKeyTaps` (the two event taps a ⌘Tab session needs), `NativeCommandTab` (turns macOS's own ⌘Tab off while DockFlip runs). |
| `Switcher/` | The ⌘Tab switcher: controller, Flip 3D view, selection and type-to-filter rules, `SwitcherStack` (which cards are drawn). |
| `Dock/` | `DockController`: watches the real Dock (hovered icon, clicks, ⌃⌥1…9; the click tap is in `DockController+Clicks`); `DockPress` tells a click from a drag or press-and-hold, which go on to the Dock; `DockClick` decides what a click does; `DockAppOrder` finds the n-th app for ⌃⌥1…9, reading the Dock's icons only up to it. |
| `WindowList/` | The window list above a Dock icon: popup controller, views, browser tab reading and the tab list. |
| `WindowLayout/` | Snapping (rules in `SnapEngine`, input in `SnapController`, drag or click in `SnapDrag`, the drag preview), Show Desktop, macOS's own edge tiling switch and the one-time hint about it in the preview (`EdgeTilingHint`). |
| `Previews/` | Opt-in thumbnails and every safety rule around them. |
| `Placement/` | Window positions remembered per display setup, kept in UserDefaults until the Mac restarts. |
| `Cleanup/` | Usage tracking, the Clean Up window and the apps it never suggests (`KeptApps`). |
| `UI/` | Small shared pieces: panels, the mini-map, window colours, `WindowPresenter`. |
| `Diagnostics/` | Logging, timing statistics, the debug log export. |

Pure rules with no AppKit in them (`SnapEngine`, `SnapDrag`, `EdgeTilingHint`, `SwitcherSelection`,
`SwitcherFilter`, `SwitcherRelease`, `SwitcherStack`, `SwitcherPreviews`, `CleanupEngine`, `TabTitle`, `MRUList`, `Geometry`) are unit-tested
in `Tests/DockFlipKitTests`. So are the smaller decisions beside the AppKit code
that acts on them: `SwitcherReveal`, `DockPress`, `DockClick`, `DockAppOrder`,
`HotKeyRegistration`, `ShortcutConflicts`, `PlacementLayouts`, `CloseFollowUp`,
`QuitFollowUp`, `UsageDates`, `CleanupSelection`, `KeptApps`, `SetupEnd`,
`LoginItemProblem`, `ThumbnailAccess`, `DebugLogFile` and `UnavailableFeature`.

The tests mirror the source folders: each type's suite is in
`Tests/DockFlipKitTests/<Feature>/<Type>Tests.swift` (`Core/MRUListTests.swift`).
The Dock list's sizing rules (`WindowListLayout`) are tested there too.
So is the ⌘Tab flow in `SwitcherController` (open, step, release, filter, cancel):
it gets its windows, focusing and the ⌘ state as closures and draws through a
`SwitcherPresenter` (`SwitcherPanel` in the app), so tests pass fakes for all of them.
`SwitcherViewTimingTests` draws the real `SwitcherView` with 60 windows in an
invisible panel and holds it to SCOPE's ⌘Tab budget; it needs a window server.

## Key ideas

- **Accessibility lists only the current Space.** Windows on other desktops and
  full-screen apps come from the window server (`WindowServer.inventory`) and
  are reached with AltTab's element-id walk (`WindowServer.findWindows`).
- **A failed Accessibility read is not an answer.** Slow apps (Chrome, Office)
  time out; the registry keeps what it knew and asks again, never concluding
  "no windows".
- **DockFlip never activates itself.** Its panels are non-activating; the ⌘Tab
  panel becomes key without activating the app, so the app you were in stays
  active and its secure keyboard input does not block the switcher.
- **⌘Tab survives secure keyboard input.** Carbon hot keys still fire, the
  listen-only modifier tap still sees ⌘ released, and the key panel gets the
  rest as ordinary key events.
- **Dock hover comes from the Dock itself** (`kAXSelectedChildrenChangedNotification`
  on its icon list); a mouse-move monitor exists only while the mouse is on the
  Dock or the list, to notice it leaving.
- **A click costs nothing.** Drag-to-edge snapping sees every left click on the
  Mac, so a mouse down only stores where it was; `SnapDrag` reads the window list
  once the mouse has moved 8 points, and takes the window's frame from the
  registry, which the moved and resized notifications keep current.
- **No tap waits on an app.** The Dock click tap answers from memory
  (`DockClick`: the highlighted icon, the registry's windows) and does the
  click's work after it has answered. The registry's calls to an app (focus,
  minimize, close and its follow-up looks, moving and resizing, the hover probe)
  run on that app's own queue (`AppQueues`), so a
  hung app, which answers only after the 1 s timeout, never holds up a click.

## Strings and languages

User-facing text is English in the code and is the key: `L("Clean Up…")` in
AppKit code, `Text("Clean Up")` in SwiftUI. Translations live in
`Resources/<language>.lproj/Localizable.strings`. When you add or change a
string, add it to every language file (English as a placeholder is fine; a
missing entry shows English).

## Building without Xcode

The Command Line Tools cannot expand Swift macros, so SwiftUI's `@State` is
not used anywhere: view state lives in `ObservableObject` models.
