// Writes the homepage once per language, for search engines.
//
// site/index.html is English, and site/i18n.js swaps its text in the browser,
// so a crawler only ever saw English. At deploy, .github/workflows/pages.yml
// copies site/ to _site/ and runs `node scripts/build-site.mjs _site`, which
// writes _site/<lang>/index.html with the strings from site/i18n/<lang>.js
// already in place, adds hreflang links between every language's page, and
// writes sitemap.xml. Plain Node, no packages.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';

const BASE = 'https://geezery.github.io/DockFlip/';
const out = process.argv[2];
if (!out) throw new Error('usage: node scripts/build-site.mjs <site folder>');

const read = f => fs.readFileSync(path.join(out, f), 'utf8');
const page = read('index.html');

// The language table lives in i18n.js; take its object literal as it is.
const table = read('i18n.js').match(/const LANGS = (\{[\s\S]*?\n {2}\});/);
if (!table) throw new Error('i18n.js: LANGS not found');
const LANGS = vm.runInNewContext('(' + table[1] + ')');

// Each language file assigns window.DockFlipI18n[lang].
const sandbox = { window: {} };
for (const code of Object.keys(LANGS)) {
  if (code === 'en') continue;
  vm.runInNewContext(read(`i18n/${code}.js`), sandbox, { filename: `i18n/${code}.js` });
}
const T = sandbox.window.DockFlipI18n || {};

const urlOf = code => BASE + (code === 'en' ? '' : code + '/');
const attr = s => s.replace(/<[^>]*>/g, '').replace(/&/g, '&amp;').replace(/"/g, '&quot;');

// Every element with data-i18n="key": where its inner HTML starts and ends.
function elements(html) {
  const found = [];
  const open = /<([a-zA-Z0-9]+)\b[^>]*\bdata-i18n="([^"]+)"[^>]*>/g;
  let m;
  while ((m = open.exec(html))) {
    const tag = m[1].toLowerCase();
    const start = m.index + m[0].length;
    const re = new RegExp(`<(/?)${tag}\\b[^>]*>`, 'gi');
    re.lastIndex = start;
    let depth = 1, end = -1, t;
    while ((t = re.exec(html))) {
      depth += t[1] ? -1 : 1;
      if (depth === 0) { end = t.index; break; }
    }
    if (end < 0) throw new Error(`no </${tag}> for data-i18n="${m[2]}"`);
    found.push({ key: m[2], start, end });
  }
  found.forEach((e, i) => {
    if (i && e.start < found[i - 1].end) throw new Error(`data-i18n="${e.key}" sits inside another`);
  });
  return found;
}

const spots = elements(page);
const EN = Object.fromEntries(spots.map(e => [e.key, page.slice(e.start, e.end)]));
EN['meta.desc'] = (page.match(/data-i18n-content="meta\.desc"[^>]*\bcontent="([^"]*)"/) || [])[1];
if (!EN['meta.desc']) throw new Error('index.html: no meta.desc');

// Pictures: <img data-i18n-alt="key" alt="English">. A picture without a key is
// decoration and says so (alt="" aria-hidden="true"); every other one needs
// words, for screen readers and image search, in every language.
const ALT = /<img\b[^>]*>/g;
const altOf = tag => (tag.match(/\salt="([^"]*)"/) || [])[1];
const altKeys = [];
for (const tag of page.match(ALT) || []) {
  const key = (tag.match(/\sdata-i18n-alt="([^"]+)"/) || [])[1];
  if (key) {
    if (!altOf(tag)) throw new Error(`index.html: <img data-i18n-alt="${key}"> has no English alt`);
    EN[key] = altOf(tag);
    altKeys.push(key);
  } else if (altOf(tag) !== '' || !/\saria-hidden="true"/.test(tag)) {
    throw new Error(`index.html: ${tag} needs data-i18n-alt, or alt="" aria-hidden="true" if it is decoration`);
  }
}
for (const [code, dict] of Object.entries(T)) {
  const missing = altKeys.filter(k => !dict[k]);
  if (missing.length) throw new Error(`i18n/${code}.js: no alt text for ${missing.join(', ')}`);
}

// A key a language file has but the page doesn't is a leftover from old text.
for (const [code, dict] of Object.entries(T)) {
  const stale = Object.keys(dict).filter(k => !(k in EN));
  if (stale.length) throw new Error(`i18n/${code}.js: keys not on the page: ${stale.join(', ')}`);
}

const alternates = Object.keys(LANGS)
  .map(code => `<link rel="alternate" hreflang="${code}" href="${urlOf(code)}">`)
  .concat(`<link rel="alternate" hreflang="x-default" href="${urlOf('en')}">`)
  .join('\n');

function render(code) {
  const dict = code === 'en' ? {} : T[code] || {};
  const names = LANGS[code];
  const fill = s => s.replace(/\{m\}/g, names.m).replace(/\{w\}/g, names.w);
  const text = key => {
    if (key === 'who.mi') return Array.from(names.m)[0];
    if (key === 'who.wi') return Array.from(names.w)[0];
    return fill(dict[key] !== undefined ? dict[key] : EN[key]);
  };

  // English too: its names are {m} and {w} until filled in.
  let html = page;
  for (const e of [...spots].reverse()) html = html.slice(0, e.start) + text(e.key) + html.slice(e.end);
  if (code !== 'en') {
    html = html.replace(/(data-i18n-content="([^"]+)"[^>]*\bcontent=")[^"]*"/g,
      (_, head, key) => head + attr(text(key)) + '"');
    html = html.replace(ALT, tag => {
      const key = (tag.match(/\sdata-i18n-alt="([^"]+)"/) || [])[1];
      return key ? tag.replace(/(\salt=")[^"]*"/, (_, head) => head + attr(text(key)) + '"') : tag;
    });
    html = html.replace(/<html lang="en">/, `<html lang="${code}" data-lang="${code}">`);
    html = html.replace(/(<meta property="og:url" content=")[^"]*"/, `$1${urlOf(code)}"`);
    html = html.replace(/(<link rel="canonical" href=")[^"]*"/, `$1${urlOf(code)}"`);
    html = html.replace(/("description": )"[^"]*"/, (_, head) => head + JSON.stringify(text('meta.desc').replace(/<[^>]*>/g, '')));
    // The page sits one folder down: point relative links back up.
    html = html.replace(/(\s(?:src|href)=")(?![a-z][a-z0-9+.-]*:|#|\/)/gi, '$1../');
    html = html.replace(/url\((?![a-z]+:|\/)/g, 'url(../');
  }
  html = html.replace(/<!-- hreflang alternates[^>]*-->/, alternates);
  if (!html.includes('hreflang="x-default"')) throw new Error('index.html: hreflang marker missing');
  return html;
}

for (const code of Object.keys(LANGS)) {
  const file = code === 'en' ? 'index.html' : `${code}/index.html`;
  fs.mkdirSync(path.dirname(path.join(out, file)), { recursive: true });
  fs.writeFileSync(path.join(out, file), render(code));
}

const links = Object.keys(LANGS)
  .map(code => `    <xhtml:link rel="alternate" hreflang="${code}" href="${urlOf(code)}"/>`)
  .join('\n');
const sitemap = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${Object.keys(LANGS).map(code => `  <url>
    <loc>${urlOf(code)}</loc>
${links}
  </url>`).join('\n')}
</urlset>
`;
fs.writeFileSync(path.join(out, 'sitemap.xml'), sitemap);
console.log(`Wrote ${Object.keys(LANGS).length} pages and sitemap.xml to ${out}`);
