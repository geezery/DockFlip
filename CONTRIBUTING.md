# Contributing to DockFlip

Thanks for stopping by. DockFlip is small on purpose, and a few rules keep it
that way.

## The one question

Every idea gets the same question: **is this one of the best bits of Windows?**
Would someone who just moved to a Mac miss it in their first week, and still miss
it a month later?

- "⌘Tab should show every window, like Alt+Tab": yes, that's the whole app.
- "Drag a window to a corner for a quarter": yes.
- "Bring back the Start menu": we hear you, and the answer is still no.
- "A setting for the stack angle": no. Pick the best angle and send that.

Not sure? Open an issue before writing code. A two-line issue is a lot cheaper
than a two-thousand-line pull request we have to say no to.
[SCOPE.md](SCOPE.md) has the full list of what's in and what's out.

## House rules

1. **No third-party dependencies.** Apple frameworks only.
2. **No networking code.** Not even an update check. Especially not an update
   check.
3. **No polling and no repeating timers.** React to Accessibility, NSWorkspace
   and input events. An app that sits in the background all day should cost
   nothing while nothing happens.
4. **Reliability first.** Test with Electron apps (Slack, VS Code), Finder,
   Safari, Chrome, Terminal, sleep and wake, and plugging a display in and out.
   A feature that works 95% of the time is a bug that happens 5% of the time.
5. **Window and tab titles never go into the log.**

## Build

You need the Command Line Tools. Xcode is optional: it works if you have it, but
there's no need to install it.

```sh
xcode-select --install   # once
make test
make run
```

## Code style

- Swift. AppKit for windows and panels, SwiftUI for what's inside them.
- **No SwiftUI macros** (`@State`, `@Observable`, `@Entry`, `#Preview` and so
  on). Their implementations ship only with full Xcode, and DockFlip has to
  build with the Command Line Tools alone. Keep view state in an
  `ObservableObject` model.
- UI state lives on the main actor; C callbacks hop in with
  `MainActor.assumeIsolated`.
- Pure logic (ordering, geometry, selection) lives in small value types with
  unit tests.
- User-facing strings are English, and the English text is the key: `L("…")` in
  AppKit code, `Text("…")` in SwiftUI. Add every new string to each
  `Resources/*.lproj/Localizable.strings` file. English as a placeholder is fine.
- [ARCHITECTURE.md](ARCHITECTURE.md) shows where things live. New code goes into
  the folder of the feature it belongs to; shared views go to `UI/`.

## Releases

Maintainers: see [RELEASING.md](RELEASING.md). In short, push a `v*` tag.

## Translations

Native speakers are very welcome to improve any of the 15 languages. Edit
`Resources/<language>.lproj/Localizable.strings` and open a pull request. If a
translation makes you wince, it probably made others wince too.

## License

By contributing you agree that your contribution is licensed under GPL-3.0.
