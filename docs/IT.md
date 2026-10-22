# DockFlip for IT

Rolling out Macs to people who come from Windows? DockFlip makes the Mac behave
the way their hands already expect: window lists in the Dock, a ⌘Tab that
switches windows, and snapping. This page is for whoever manages those Macs.

With an MDM, users never see a permission prompt or a Gatekeeper warning. They
log in, and DockFlip just works.

## What's in each release

Every [release](https://github.com/geezery/DockFlip/releases/latest) has:

| File | For |
|---|---|
| `DockFlip-<version>.pkg` | Installs `DockFlip.app` into `/Applications` |
| `DockFlip-Accessibility.mobileconfig` | Pre-approves the Accessibility permission (PPPC) |
| `DockFlip.dmg` | Manual installs |

## Rollout in three steps

1. **Upload the profile.** Add `DockFlip-Accessibility.mobileconfig` to your MDM
   (Jamf Pro, Microsoft Intune, Kandji, Mosyle and others) and scope it to the
   Macs. It pins DockFlip's code signature, so it only covers the genuine,
   release-signed app. A profile only takes effect when an MDM delivers it;
   double-clicking it on a Mac grants nothing.
2. **Deploy the app.** Use the `.pkg`, or the `.dmg` if your MDM prefers it.
   Apps installed by an MDM aren't quarantined, so there's no "Open Anyway"
   step.
3. **Done.** On first launch DockFlip finds Accessibility already allowed. The
   user confirms a short setup and picks whether to turn on thumbnails, which
   are off by default.

**Package signing.** The `.pkg` isn't signed with an Apple Developer ID yet. Your
MDM's standard app or policy deployment handles that fine, but some methods,
such as MDM `InstallApplication` commands, require a Developer ID–signed
package. That comes with notarization, which is on the way.

## Permissions

| Permission | Needed | Can an MDM pre-approve it? |
|---|---|---|
| Accessibility | Yes | Yes, with the profile above |
| Screen Recording | No, only for the opt-in thumbnails | No. macOS lets a profile allow the user to approve it, nothing more |

DockFlip has **no networking code**, no telemetry and no third-party code.
Window and tab titles never reach its log. See [SECURITY.md](../SECURITY.md)
for the details and how to verify them.

## Updates

DockFlip doesn't update itself, because it has no networking code. Deploy each
new `.pkg` the way you deployed the first one. Every release is signed with the
same identity, so the Accessibility profile keeps working across versions and
you don't need to re-upload it.

## Settings you can manage

DockFlip keeps its settings in the `io.github.dockflip.DockFlip` preferences
domain. You can set them with a custom settings or managed preferences payload:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `previewsEnabled` | Boolean | `false` | Real window thumbnails (needs Screen Recording) |
| `shortcutsEnabled` | Boolean | `true` | ⌘Tab switcher and ⌃⌥ shortcuts |

Launch at login is turned on during the user's first setup.

## Building the profile yourself

If you build DockFlip from source, or want to check the profile, generate it
from any copy of the app:

```sh
python3 scripts/make-pppc-profile.py /Applications/DockFlip.app DockFlip-Accessibility.mobileconfig
```

## Questions

Open an [issue](https://github.com/geezery/DockFlip/issues). Mentioning which
MDM you use helps.
