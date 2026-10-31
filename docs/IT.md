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
| `*.sha256` | SHA-256 checksums of the `.pkg`, the profile and `DockFlip-<version>.dmg` |

## Verify the files

Every release is built by GitHub Actions from the tagged source. The `.pkg`,
the profile and the disk image each come with a build-provenance attestation
and a SHA-256 checksum, so you can check what you upload to your MDM is exactly
what that build made. With the [GitHub CLI](https://cli.github.com):

```sh
gh attestation verify DockFlip-<version>.pkg --repo geezery/DockFlip
gh attestation verify DockFlip-Accessibility.mobileconfig --repo geezery/DockFlip
shasum -a 256 -c DockFlip-<version>.pkg.sha256
shasum -a 256 -c DockFlip-Accessibility.mobileconfig.sha256
```

Keep the `.sha256` file in the same folder as the file it names.

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
   are off by default. If your profile sets `previewsEnabled`, setup skips
   that question and keeps your value.

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

## Tested on

DockFlip needs macOS 26 or later. What has been checked on which version (the
same table as on the wiki's
[Troubleshooting](https://github.com/geezery/DockFlip/wiki/Troubleshooting#tested-on) page):

| macOS | Checked how | Turning off macOS's own ⌘Tab | Window tracking | Windows on other Spaces | Dock lists |
|---|---|---|---|---|---|
| 26, GitHub's `macos-26` runner | Every change: build, tests, start and quit | Found | Not checked | Not checked | Not checked |

CI can't grant Accessibility, so the last three columns need a real Mac. Before
a new macOS version reaches everyone, try it on one Mac: DockFlip relies on a
few macOS calls Apple doesn't document, and if the update broke one, the menu
bar menu says so on that Mac (*Dock lists: not available on this macOS version*,
for example), and **Save Debug Log…** names the call in its *Self-check*
section.

## Settings you can manage

DockFlip keeps its settings in the `io.github.dockflip.DockFlip` preferences
domain. You can set them with a custom settings or managed preferences payload:

| Key | Type | Default | Meaning |
|---|---|---|---|
| `previewsEnabled` | Boolean | `false` | Real window thumbnails (needs Screen Recording) |
| `shortcutsEnabled` | Boolean | `true` | ⌘Tab switcher and ⌃⌥ shortcuts |
| `switcherStyle` | String | `flip3D` | ⌘Tab look: `flip3D` (Windows 7 Flip 3D) or `grid` (Windows 11) |

A key your profile manages is locked: DockFlip's Settings greys out its switch
and shows "Managed by your organization" under it, and DockFlip keeps following
the managed value.

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
