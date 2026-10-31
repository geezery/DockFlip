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

// Search results cut a description at about 155 characters; the privacy
// point comes first so that it is never the part cut.
test('every page\'s description fits a search result and starts with the privacy point', () => {
  for (const code of Object.keys(LANGS)) {
    const html = pageOf(code);
    const desc = (html.match(/<meta name="description"[^>]*\bcontent="([^"]*)"/) || [])[1];
    expect(desc, `${code}: no meta description`);
    const length = Array.from(desc.replace(/&amp;/g, '&').replace(/&quot;/g, '"')).length;
    expect(length <= 155, `${code}: description is ${length} characters, at most 155 show in search results`);
    const og = (html.match(/<meta property="og:description"[^>]*\bcontent="([^"]*)"/) || [])[1];
    expect(og === desc, `${code}: og:description differs from the description`);
  }
  const en = english.match(/<meta name="description"[^>]*\bcontent="([^"]*)"/)[1];
  expect(/^[^:]*one permission, no screen recording:/.test(en), 'English description: the privacy point is not first');
});

// Runs site/i18n.js against a page's <html> attributes with a stand-in DOM,
// picks a language in the footer menu, and returns where the browser went
// (or null when the text was swapped in place).
function chooseLanguage(html, code) {
  const attrs = {};
  for (const [, k, v] of html.match(/<html\b[^>]*>/)[0].matchAll(/\s([a-z-]+)(?:="([^"]*)")?/g)) attrs[k] = v ?? '';
  let onChange = null;
  const select = { value: '', appendChild() {}, addEventListener: (_, f) => { onChange = f; } };
  const documentElement = {
    lang: attrs.lang,
    dataset: attrs['data-lang'] ? { lang: attrs['data-lang'] } : {},
    hasAttribute: name => name in attrs,
  };
  const location = { href: 'unchanged', search: '' };
  const context = {
    window: { DockFlipI18n: T },
    document: {
      documentElement, title: '',
      querySelectorAll: () => [],
      getElementById: id => (id === 'lang' ? select : null),
      createElement: () => ({}),
    },
    location, URLSearchParams, localStorage: { getItem: () => null, setItem() {} },
    navigator: { languages: ['en'] },
  };
  vm.runInNewContext(fs.readFileSync(path.join(site, 'i18n.js'), 'utf8'), context);
  select.value = code;
  onChange();
  return location.href === 'unchanged' ? null : location.href;
}

test('the language menu on the deployed root page goes to that language\'s page', () => {
  expect(chooseLanguage(english, 'fi') === './fi/', `root page, Suomi: went to ${chooseLanguage(english, 'fi')}`);
  expect(chooseLanguage(english, 'en') === './', 'root page, English: did not stay on the root');
  expect(chooseLanguage(pageOf('de'), 'fi') === '../fi/', 'German page, Suomi: did not go to ../fi/');
  expect(chooseLanguage(pageOf('de'), 'en') === '../', 'German page, English: did not go to the root');
  // site/index.html opened from disk has no language pages beside it.
  const raw = fs.readFileSync(path.join(site, 'index.html'), 'utf8');
  expect(chooseLanguage(raw, 'fi') === null, 'site/index.html: should swap text in place, not navigate');
});

// WCAG AA: 4.5:1 for body text. The colours are the :root tokens in
// index.html; the nav is translucent, so its worst case is over a white
// picture scrolling beneath it.
test('text colours meet WCAG AA contrast against the backgrounds they sit on', () => {
  const css = english.match(/:root\{([^}]*)\}/)[1];
  const token = name => css.match(new RegExp(`--${name}:(#[0-9a-f]{6})`, 'i'))[1];
  const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
  const lum = c => {
    const [r, g, b] = c.map(v => v / 255).map(v => (v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const nav = english.match(/nav\{[^}]*background:rgba\((\d+),(\d+),(\d+),([.\d]+)\)/);
  const alpha = Number(nav[4]);
  const navOverWhite = [1, 2, 3].map(i => Number(nav[i]) * alpha + 255 * (1 - alpha));
  const bg = rgb(token('bg')), card = rgb(token('card'));
  const pairs = [
    ['text on bg', token('text'), bg], ['text on card', token('text'), card],
    ['muted on bg', token('muted'), bg], ['muted on card', token('muted'), card],
    ['accent on bg', token('em'), bg], ['accent on card', token('em'), card],
    ['ink on card', token('ink'), card], ['button text on accent', '#06120d', rgb(token('em'))],
    ['nav links over a white picture', token('muted'), navOverWhite],
  ];
  for (const [name, fg, back] of pairs) {
    const r = ratio(rgb(fg), back);
    expect(r >= 4.5, `${name}: ${r.toFixed(2)}:1, AA needs 4.5:1`);
  }
});

fs.rmSync(out, { recursive: true, force: true });
if (failed) { console.log(`${failed} failed`); process.exit(1); }
console.log('all passed');
