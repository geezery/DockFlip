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

## Before a release: re-check the comparison

README's [How it compares](README.md#how-it-compares) names other apps'
features and prices, and those change. Before you tag:

1. Open each link in the "Sources:" line under that table and check every row.
2. Fix any row that changed, in every file that repeats it: `README.md`,
   `site/llms.txt`, `site/llms-full.txt`, `docs/wiki/Features.md`, `docs/wiki/FAQ.md`, and the
   homepage's `cmp.*` strings in `site/index.html` and all of `site/i18n/*.js`.
3. Set the new date in all of them, also when nothing changed: README's
   "Checked on", `site/llms.txt`, `site/llms-full.txt`, `docs/wiki/Features.md`,
   the comment and `cmp.src` in `site/index.html`, and `cmp.src` in each
   `site/i18n/*.js`. `node scripts/build-site-tests.mjs` fails while the dates
   disagree.

## After a release: tell AI readers

`site/llms.txt` and `site/llms-full.txt` start with a *Version* section, so a
language model does not mix one release's docs with another's. Once the release
is out, set the new version, its tag link, the release date and *Last updated*
in both, and fix anything the release changed in `site/llms-full.txt`.
`node scripts/build-site-tests.mjs` fails while the two disagree.

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
