# Releasing DockFlip

A release is a tag. GitHub Actions does the rest: it builds a universal
DockFlip.app (Apple silicon and Intel), signs it with the release identity,
packs `DockFlip-<version>.dmg`, attests its provenance and publishes it on
[Releases](https://github.com/geezery/DockFlip/releases) with the install steps.

## Make a release

In Terminal on a Mac, or Git Bash on Windows, inside your DockFlip folder:

```sh
git pull
git tag v0.3.1
git push origin v0.3.1
```

Use the next free version number. The version in the app comes from the tag.

Then watch **Actions → Release**. It takes about five minutes, and the release
appears under **Releases** when it's done. The README's Download button always
points at the newest one.

## Numbering

- `v0.3.1`: fixes only
- `v0.4.0`: new features
- `v1.0.0`: the first release you'd recommend to your least technical colleague

## If something goes wrong

- **The workflow fails before building:** the `RELEASE_IDENTITY` secret is
  missing. Run `./scripts/make-release-identity.sh` again. It reuses the backup
  in `~/.dockflip/` (Windows) or `~/Library/Application Support/DockFlip/` (Mac).
- **Build it again for the same tag:** Actions → Release → *Run workflow*, and
  enter the tag. The files on the existing release are replaced.
- **A broken release went out:** fix it, then tag the next version. Don't
  reuse a version number, because people may have downloaded the broken one.

## The release identity

Every release is signed with the same self-signed "DockFlip Release" identity,
so users keep their Accessibility permission across updates. Its only copies
are the backup file and the `RELEASE_IDENTITY` secret. **Keep the backup in
your password manager.** If it's lost, the next release is signed with a new
identity and every user has to allow DockFlip once more.
