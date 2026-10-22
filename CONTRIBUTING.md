# Contributing to DockFlip

Thanks for helping. A few rules keep DockFlip small and predictable.

## Before you open a pull request

1. **Check [SCOPE.md](SCOPE.md).** Windows 11 default behaviour is the spec.
   New settings and features beyond it need a strong case — open an issue first.
2. **No third-party dependencies.** Apple frameworks only.
3. **No networking code.** Not even an update check.
4. **No polling.** React to Accessibility and NSWorkspace notifications.
5. **Reliability first.** Test with Electron apps (Slack, VS Code), Finder,
   Safari, Chrome, Terminal, sleep/wake and plugging a display in and out.

## Build

```sh
xcode-select --install   # once
make test
make run
```

## Code style

- Swift, AppKit for windows and panels, SwiftUI for content.
- **No SwiftUI macros** (`@State`, `@Observable`, `@Entry`, `#Preview` …): their
  implementations ship only with full Xcode, and DockFlip must build with the
  Command Line Tools alone. Keep view state in an `ObservableObject` model.
- UI state on the main actor; C callbacks hop in with `MainActor.assumeIsolated`.
- Pure logic (ordering, geometry, selection) lives in small value types with
  unit tests.
- User-facing strings are English and use the English text as the key
  (`L("…")`), so translations can be added later.

## License

By contributing you agree that your contribution is licensed under GPL-3.0.
