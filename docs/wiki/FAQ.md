# FAQ

**Is it really free?**
Yes. GPL-3.0, no trial, no "Pro", no subscription, and no account.

**Does it replace my Dock?**
No. The Dock stays the real macOS Dock. DockFlip adds the window lists and the
click behaviour on top of it.

**Why does ⌘Tab switch windows and not apps?**
Because that's what Alt+Tab does, and it's the thing Windows people miss most.
macOS's app switcher returns when you quit DockFlip, and ⌘\` still cycles one
app's windows.

**Why Flip 3D, of all things?**
Because it was great and nobody should have taken it away. A stack also fits
more windows on screen than a grid, and the one in front is unmistakable.

**Why ⌃⌥ instead of ⌘ for snapping?**
⌘ shortcuts belong to apps, and Globe shortcuts belong to macOS's own tiling.
⌃⌥ is the closest thing a Mac keyboard has to a free Win key.

**Can I change the shortcuts?**
Not yet, on purpose: good defaults beat a settings window. You can switch all
shortcuts off in Settings.

**Why macOS 26 only?**
DockFlip relies on APIs that newer macOS versions do better, and one
well-tested version beats five shaky ones. Consider it a nudge to update.

**Why isn't it on the Mac App Store?**
The App Store sandbox doesn't allow the Accessibility API, and without that
DockFlip can't see a single window.

**Why build from source instead of downloading an app?**
Apps distributed outside the App Store need Apple's notarization (a paid
developer account) to open without warnings. Building locally sidesteps that,
and `make install` does all the work. A Homebrew tap is on the [roadmap](https://github.com/geezery/DockFlip/blob/main/ROADMAP.md).

**Does it slow my Mac down?**
It shouldn't. DockFlip doesn't poll and runs no repeating timers. When nothing
happens, it does nothing.

**Can you add thirds, gaps or "almost maximize"?**
That's Rectangle's job, and Rectangle does it brilliantly. DockFlip sticks to the
best bits of Windows; see [SCOPE.md](https://github.com/geezery/DockFlip/blob/main/SCOPE.md).

**Will there be a Start menu?**
No. ⌘Space is right there, and it's better.
