# Troubleshooting

## Which version do I have?

The first line of the menu bar menu says it, for example *DockFlip 0.3.0
(c79a704)*. The part in brackets is the commit the app was built from. Builds
from source all carry the same version number, so the commit tells you whether
yours has a fix. Settings and **Save Debug Log…** show the same.

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

## The menu says *⌘Tab: used by another app*

Another app, usually AltTab, already holds ⌘Tab. DockFlip then leaves ⌘Tab to
macOS's own switcher instead of switching it off, and its ⌃⌥ shortcuts keep
working. Quit the other app (and remove it from *Login Items*), then turn
**Keyboard shortcuts** off and on in DockFlip's Settings, or restart DockFlip.
**Save Debug Log…** names each shortcut another app holds.

*⌘Tab: not active* with **Restart DockFlip** below it means macOS refused
DockFlip's key taps: choose **Restart DockFlip**.

## ⌃⌥← does another app's thing, or nothing

Rectangle's and Magnet's default shortcuts are ⌃⌥ with the arrows, D and E,
the same keys as DockFlip's, and whichever app starts first gets them. The menu
bar menu then shows a line such as *⌃⌥← ⌃⌥→ ⌃⌥D: used by another app*, naming
Rectangle, Rectangle Pro, Magnet or Spectacle below it when one of them is
running (macOS doesn't say which app holds a key). Quit that app or change its
shortcuts, then click the line: DockFlip asks for the shortcuts again. AltTab
is named the same way under *⌘Tab: used by another app*.

## An app's windows don't show up

- **Is a window actually open?** The dot under a Dock icon means the app is
  running, not that it has windows. Chrome and friends love running with zero
  windows.
- **Slow apps** (Office, sometimes Chrome) can take a moment to answer. DockFlip
  asks again rather than concluding "no windows".
- Still missing? Turn on **Debug Logging** in the menu bar menu, reproduce the
  problem, choose **Save Debug Log…**, pick where to save it (the Desktop is
  suggested) and attach the file to a
  [bug report](https://github.com/geezery/DockFlip/issues/new/choose). The log
  never contains window or tab titles, and saving it asks for no permission. If
  it can't be saved, DockFlip says why; pick another folder.

## Browser tabs aren't listed

- Tabs show when a window has more than one tab.
- **Firefox** turns on its accessibility engine the first time DockFlip asks it
  for tabs. Give it a second.

## Thumbnails are on but no pictures show

Thumbnails need *Screen & System Audio Recording*. While it isn't allowed, the
menu bar menu shows *Screen Recording is not allowed yet*; click it for Settings,
which says so under **Window thumbnails**: press **Open System Settings**,
allow DockFlip there, then press **Restart DockFlip**, because macOS often
applies the permission only after a restart.

## DockFlip doesn't start when I log in

Launch at login lives in macOS, in *System Settings → General → Login Items &
Extensions*. If DockFlip is switched off there, the **Launch at login** switch
can't turn it back on: Settings says so under the switch. Press **Open Login
Items**, switch DockFlip on there, and the switch in Settings follows. If macOS
refuses for another reason, Settings shows macOS's own words.

## Snapping fights with macOS

If windows jump around twice when you drag them to an edge, macOS's own tiling
is also on. Setup offers to turn it off, and whenever it is back on (switched on
again, or reset by a macOS update) the menu bar menu shows **Turn Off macOS Edge
Tiling**. You can also switch off *Drag windows to screen edges to tile* in
*System Settings → Desktop & Dock*.

## I picked a language I can't read

Menu bar menu → 🌐 → **English**. See [[Languages]].

## `make install` asks for my password

That happens once, to trust DockFlip's local signing certificate. See
[[Installation]] for why.

## Starting fresh

```sh
make uninstall && make install
```
