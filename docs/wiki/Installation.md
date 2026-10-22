# Installation

## Download (recommended)

**[⬇ Download the latest DockFlip](https://github.com/geezery/DockFlip/releases/latest)**: one disk image for
Apple silicon and Intel Macs running **macOS 26 or later**.

1. Open the disk image and drag **DockFlip** to **Applications**.
2. Open DockFlip. macOS says it can't check the app for malware: press **Done**.
3. Open **System Settings → Privacy & Security**, scroll down and press
   **Open Anyway** next to DockFlip. Confirm with your password or Touch ID.
4. Continue with the setup below.

Steps 2 and 3 are Apple's warning for apps from developers who don't pay for
notarization (99 € a year). They go away once DockFlip is notarized; that's what
the ☕ [coffee](https://github.com/sponsors/geezery?frequency=one-time) is for.

## Build from source (developers)

- **macOS 26 or later.**
- **Apple's Command Line Tools.** They're free and you don't need an Apple
  account. **Xcode is optional:** if you already have it, that works too.

```sh
xcode-select --install                 # once; skip it if you already have Xcode or the tools
git clone https://github.com/geezery/DockFlip.git
cd DockFlip
make install
```

The first `make install` asks for your login password **once**, to trust a
local code-signing certificate (see below). A source build and a downloaded
release are signed differently, so switching between them means allowing
Accessibility once more.

## Setup (about 30 seconds)

1. **Allow Accessibility.** The setup window opens *System Settings → Privacy &
   Security → Accessibility* for you. Switch DockFlip on. This is the only
   permission DockFlip needs.
2. **Choose thumbnails, or don't.** Thumbnails show real pictures of your
   windows and need Screen Recording permission. Without them, DockFlip shows
   window cards and mini-maps, which work surprisingly well. You can change
   your mind later in Settings.
3. **Done.** Hover a Dock icon, press ⌘Tab, or press ⌃⌥←.

If macOS's own edge tiling is on, setup offers to turn it off, because two
snapping systems fighting over one window isn't fun for anyone.

## Why a signing certificate?

macOS ties permissions to an app's code signature. An unsigned or ad-hoc
signed app gets a new identity on every build, and macOS forgets that you
allowed it. So `make install` creates a self-signed identity called
**"DockFlip Signing"** in its own keychain
(`~/Library/Keychains/dockflip-signing.keychain-db`), with a random password
stored in `~/Library/Application Support/DockFlip/`. It isn't an Apple
Developer certificate and costs nothing. It only exists so that your rebuilds
keep their permissions.

## Updating

**Downloaded:** get the new disk image, quit DockFlip, replace the app in
Applications and repeat steps 2–3 above. Your permission and settings stay,
because every release is signed with the same identity.

**From source:** `git pull && make install`.

## Uninstalling

Quit DockFlip from its menu bar menu and drag it from Applications to the Trash.
macOS's own ⌘Tab comes back as soon as DockFlip quits.

From source, `make uninstall` also removes its settings, its permissions and the
signing keychain.

## Other make targets

| Target | What it does |
|---|---|
| `make` | Build only |
| `make run` | Build and start from the build folder |
| `make test` | Run the unit tests |
| `make clean` | Remove build output |
