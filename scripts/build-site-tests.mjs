// Checks the homepage as scripts/build-site.mjs writes it: every picture has
// words in every language, and every language names the features the English
// page does. Plain Node, no packages: `node scripts/build-site-tests.mjs`.
// It builds a copy of site/ in a temp folder and never touches site/ itself.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const site = path.join(root, 'site');
const out = fs.mkdtempSync(path.join(os.tmpdir(), 'dockflip-site-'));
fs.cpSync(site, out, { recursive: true });
execFileSync(process.execPath, [path.join(root, 'scripts/build-site.mjs'), out], { stdio: 'pipe' });

const LANGS = vm.runInNewContext('(' + fs.readFileSync(path.join(site, 'i18n.js'), 'utf8')
  .match(/const LANGS = (\{[\s\S]*?\n {2}\});/)[1] + ')');
const pageOf = code => fs.readFileSync(path.join(out, code === 'en' ? '' : code, 'index.html'), 'utf8');
const sandbox = { window: {} };
for (const code of Object.keys(LANGS)) {
  if (code !== 'en') vm.runInNewContext(fs.readFileSync(path.join(site, 'i18n', code + '.js'), 'utf8'), sandbox);
}
const T = sandbox.window.DockFlipI18n;

let failed = 0;
function test(name, fn) {
  try { fn(); console.log(`ok   ${name}`); }
  catch (e) { failed++; console.log(`FAIL ${name}\n     ${e.message}`); }
}
function expect(cond, msg) { if (!cond) throw new Error(msg); }

const imgs = html => html.match(/<img\b[^>]*>/g) || [];
const altOf = tag => (tag.match(/\salt="([^"]*)"/) || [])[1];
const english = pageOf('en');

test('every picture on every language page has alt text, or is marked as decoration', () => {
  for (const code of Object.keys(LANGS)) {
    for (const tag of imgs(pageOf(code))) {
      const decoration = altOf(tag) === '' && /\saria-hidden="true"/.test(tag);
      expect(decoration || altOf(tag), `${code}: ${tag} has no alt text`);
    }
  }
});

test('the feature pictures are described in each page\'s own language', () => {
  const enAlts = imgs(english).map(altOf).filter(Boolean);
  expect(enAlts.length >= 5, `English page has ${enAlts.length} described pictures, expected 5`);
  for (const code of Object.keys(LANGS)) {
    if (code === 'en') continue;
    const alts = imgs(pageOf(code)).map(altOf).filter(Boolean);
    expect(alts.length === enAlts.length, `${code}: ${alts.length} described pictures, English has ${enAlts.length}`);
    alts.forEach((a, i) => expect(a !== enAlts[i], `${code}: picture ${i + 1} still has the English alt "${a}"`));
  }
});

test('the Snapping section names Snap Assist in every language', () => {
  expect(/data-i18n="snap\.l4"[^>]*>[^<]*<b>Snap Assist:<\/b>/.test(english), 'index.html: no snap.l4 Snap Assist bullet');
  for (const code of Object.keys(T)) expect(T[code]['snap.l4'], `i18n/${code}.js: no snap.l4`);
});

fs.rmSync(out, { recursive: true, force: true });
if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all passed');
