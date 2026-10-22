# Installation

## What you need

- **macOS 26 or later.** DockFlip uses APIs that only recent macOS versions
  have, and we'd rather do one version really well. Consider it a reason to
  update.
- **Apple's Command Line Tools.** They're free and you don't need an Apple
  account. **Xcode is optional:** if you already have it, that works too, and if
  you don't, there's no need to download it.

## Install

```sh
xcode-select --install                 # once; skip it if you already have Xcode or the tools
git clone https://github.com/geezery/DockFlip.git
cd DockFlip
make install
```

The first `make install` asks for your login password **once**, to trust a
local code-signing certificate (more on that below). After that, DockFlip
starts and opens its setup window.

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

```sh
cd DockFlip
git pull
make install
```

Your permissions and settings stay.

## Uninstalling

```sh
make uninstall
```

This removes the app, its settings, its permissions and the signing keychain.
macOS's own ⌘Tab comes back immediately.

## Other make targets

| Target | What it does |
|---|---|
| `make` | Build only |
| `make run` | Build and start from the build folder |
| `make test` | Run the unit tests |
| `make clean` | Remove build output |
