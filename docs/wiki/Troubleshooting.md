# Troubleshooting

## ⌘Tab does nothing after a rebuild

macOS may be holding on to an Accessibility entry for an older signature. Open
DockFlip's setup and press **Reset Permission**, or run:

```sh
tccutil reset Accessibility io.github.dockflip.DockFlip
```

Then allow DockFlip again in *System Settings → Privacy & Security →
Accessibility*.

## macOS's own ⌘Tab is gone

DockFlip switches it off while running and gives it back when it quits, including
when it's stopped from Terminal. If DockFlip crashed hard, start it and quit it
once, and the native switcher is back.

## An app's windows don't show up

- **Is a window actually open?** The dot under a Dock icon means the app is
  running, not that it has windows. Chrome and friends love running with zero
  windows.
- **Slow apps** (Office, sometimes Chrome) can take a moment to answer. DockFlip
  asks again rather than concluding "no windows".
- Still missing? Turn on **Debug Logging** in the menu bar menu, reproduce the
  problem, choose **Save Debug Log…** and attach the file to a
  [bug report](https://github.com/geezery/DockFlip/issues/new/choose). The log
  never contains window or tab titles.

## Browser tabs aren't listed

- Tabs show when a window has more than one tab.
- **Firefox** turns on its accessibility engine the first time DockFlip asks it
  for tabs. Give it a second.

## Snapping fights with macOS

If windows jump around twice when you drag them to an edge, macOS's own tiling
is also on. Setup offers to turn it off; you can also switch off *Drag windows
to screen edges to tile* in *System Settings → Desktop & Dock*.

## I picked a language I can't read

Menu bar menu → 🌐 → **English**. See [[Languages]].

## `make install` asks for my password

That happens once, to trust DockFlip's local signing certificate. See
[[Installation]] for why.

## Starting fresh

```sh
make uninstall && make install
```
