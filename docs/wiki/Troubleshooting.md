# Troubleshooting

## Which version do I have?

The first line of the menu bar menu says it, for example *DockFlip 0.3.0
(c79a704)*. The part in brackets is the commit the app was built from. Builds
from source all carry the same version number, so the commit tells you whether
yours has a fix. A build made with changes that commit doesn't hold says so:
*DockFlip 0.3.0 (c79a704-dirty)*. Settings and **Save Debug Log…** show the same.

## A permission is on, but DockFlip acts as if it isn't

macOS remembers each permission for one signature of the app. A build from
source (`make install`) and a download from Releases are signed differently, and
a rebuild can change the signature too. After you switch between them, or
rebuild, *System Settings* can show DockFlip switched on while macOS refuses the
new copy: ⌘Tab does nothing, or thumbnails stay empty. Switching DockFlip off
and on in System Settings does not fix it; forgetting the old entry does.

For Accessibility, open DockFlip's setup and press **Reset Permission**. Or quit
DockFlip and run, in Terminal:

```sh
tccutil reset Accessibility io.github.dockflip.DockFlip
tccutil reset ScreenCapture io.github.dockflip.DockFlip
```

The first line is Accessibility, the second *Screen & System Audio Recording*
(thumbnails). Then open DockFlip, allow it again in *System Settings → Privacy &
Security*, and restart DockFlip once, because macOS often applies a permission
only after a restart.

## macOS's own ⌘Tab is gone

DockFlip switches it off while running and gives it back when it quits, including
when it's stopped from Terminal. If DockFlip crashed hard, start it and quit it
once, and the native switcher is back.

## I switched Accessibility off while DockFlip was running

Without the permission DockFlip can show windows but can't switch to them, so
it gives ⌘Tab and its ⌃⌥ shortcuts back to macOS within a second, stops drag
snapping and Snap Assist, and opens its setup at the Accessibility step. Switch DockFlip back on in *System Settings →
Privacy & Security → Accessibility* and it restarts by itself with its own ⌘Tab.
If you'd rather not, close the setup window: macOS keeps ⌘Tab until you allow
DockFlip again (**Grant Accessibility…** in the menu) or quit it.

## The menu says *⌘Tab: used by another app*

Another app, usually AltTab, already holds ⌘Tab. DockFlip then leaves ⌘Tab to
macOS's own switcher instead of switching it off, and its ⌃⌥ shortcuts keep
working. DockFlip's Settings says the same under **Keyboard shortcuts**. Quit
the other app (and remove it from *Login Items*), then choose **Try Again** there,
or restart DockFlip.
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
is named the same way under *⌘Tab: used by another app*. Settings shows the same warning
under **Keyboard shortcuts**, with a **Try Again** button.

## The menu says *… not available on this macOS version*

DockFlip relies on a few macOS calls Apple doesn't document, and a new macOS
can change one without a crash or an error. DockFlip notices as it works, and
the menu bar menu then names the part that stopped:

| Menu line | What you notice |
|---|---|
| *Turning off macOS's own ⌘Tab: not available on this macOS version* | ⌘Tab shows macOS's app switcher as well as DockFlip's |
| *Window tracking: not available on this macOS version* | DockFlip sees no windows: the Dock lists and ⌘Tab are empty |
| *Windows on other Spaces: not available on this macOS version* | Windows on other Spaces and in full screen are missing from the lists |
| *Dock lists: not available on this macOS version* | Resting on a Dock icon opens no list, icon clicks do what they do without DockFlip, and ⌃⌥1…9 do nothing |

The rest of DockFlip keeps working, and no setting brings the part back: that
takes a DockFlip update. If only *Dock lists* shows, quit DockFlip and start it
again first, because a Dock that was still starting up looks the same. Then
please [report it](https://github.com/geezery/DockFlip/issues/new/choose) with
your macOS version (Apple menu → *About This Mac*) and the file from **Save
Debug Log…**: its *Self-check* section names the macOS call that failed.

## Tested on

DockFlip needs macOS 26 or later. What has been checked on which version:

| macOS | Checked how | Turning off macOS's own ⌘Tab | Window tracking | Windows on other Spaces | Dock lists |
|---|---|---|---|---|---|
| 26, GitHub's `macos-26` runner | Every change: build, tests, start and quit | Found | Not checked | Not checked | Not checked |

The *Toolchain* step of each [CI run](https://github.com/geezery/DockFlip/actions/workflows/ci.yml)
names the runner's exact version. A CI machine has no Accessibility permission
and no mouse on its Dock, so the last three columns can only be checked on a
real Mac: there, the *Self-check* section of **Save Debug Log…** says *ok* for
each one that works. A newer macOS than the table names may well work; if a
part stops, the menu says so (see above). A row for a real Mac is added once
someone has checked one with the debug log.

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
  it can't be saved, DockFlip says why; pick another folder. Its *Self-check*
  section says whether the private macOS calls and the Dock hook DockFlip
  relies on still work on your macOS: a line in capitals is the likely cause.

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

If System Settings already shows DockFlip allowed and pictures still don't come,
macOS is holding on to an older signature: see
[A permission is on, but DockFlip acts as if it isn't](#a-permission-is-on-but-dockflip-acts-as-if-it-isnt).

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
Tiling**; the first drag snap after DockFlip starts says so in its preview too.
You can also switch off *Drag windows to screen edges to tile* in
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
