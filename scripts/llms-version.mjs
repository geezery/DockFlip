// Names the latest release in the deployed llms.txt and llms-full.txt.
//
// Both files start with a "Version" section so an AI reader does not mix one
// release's docs with another's. Kept by hand it goes stale the day a release
// is tagged, so at deploy .github/workflows/pages.yml runs
//   node scripts/llms-version.mjs _site <tag> <released YYYY-MM-DD> <updated YYYY-MM-DD>
// on its copy of site/. release.yml starts that deploy once a release is
// published. The files in the repository keep the values written last by hand.
// Plain Node, no packages.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const FILES = ['llms.txt', 'llms-full.txt'];

const DATE = /^\d{4}-\d{2}-\d{2}$/;
const VERSION = /^\d+\.\d+\.\d+$/;

// The three lines this rewrites, each with the part that changes as a group.
// (?=\r?$): a Windows checkout may have CRLF line ends.
const LINES = [
  [/^(- Current release: DockFlip )\d+\.\d+\.\d+( \(\[release notes\]\(https:\/\/github\.com\/geezery\/DockFlip\/releases\/tag\/v)\d+\.\d+\.\d+(\), released )\d{4}-\d{2}-\d{2}(\))(?=\r?$)/m,
    v => `$1${v.version}$2${v.version}$3${v.released}$4`],
  [/^(- Last updated: )\d{4}-\d{2}-\d{2}(?=\r?$)/m, v => `$1${v.updated}`],
  [/^(- Documentation version: this file describes DockFlip )\d+\.\d+\.\d+\./m, v => `$1${v.version}.`],
];

/** Returns `text` with its Version section naming `version`, released and updated on those dates. */
export function stamp(text, { version, released, updated }) {
  if (!VERSION.test(version)) throw new Error(`not a version: ${version}`);
  if (!DATE.test(released) || !DATE.test(updated)) throw new Error(`not a date: ${released} ${updated}`);
  // A file last edited before the release still describes that release.
  if (updated < released) updated = released;
  return LINES.reduce((t, [re, to]) => {
    if (!re.test(t)) throw new Error(`no line matching ${re}`);
    return t.replace(re, to({ version, released, updated }));
  }, text);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [dir, tag, released, updated] = process.argv.slice(2);
  if (!updated) throw new Error('usage: node scripts/llms-version.mjs <site folder> <tag> <released> <updated>');
  const version = tag.replace(/^v/, '');
  for (const f of FILES) {
    const file = path.join(dir, f);
    fs.writeFileSync(file, stamp(fs.readFileSync(file, 'utf8'), { version, released, updated }));
  }
  console.log(`${FILES.join(' and ')} name DockFlip ${version}, released ${released}`);
}
