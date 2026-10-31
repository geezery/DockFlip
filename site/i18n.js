// DockFlip homepage translations. English lives in index.html itself; every
// other language overrides it key by key, and a missing key falls back to
// English. {m} and {w} are the two people the page talks about, with names
// that feel local in each language. This file holds the languages and the
// switcher; each language's strings are in site/i18n/<lang>.js. A new language
// needs a LANGS entry here, its file, and a <script> tag for it in index.html.
(function () {
  const LANGS = {
    'en':      { name: 'English',            m: 'Mark',    w: 'Anna' },
    'fi':      { name: 'Suomi',              m: 'Pentti',  w: 'Minna' },
    'sv':      { name: 'Svenska',            m: 'Lars',    w: 'Karin' },
    'da':      { name: 'Dansk',              m: 'Henrik',  w: 'Mette' },
    'nb':      { name: 'Norsk',              m: 'Geir',    w: 'Hilde' },
    'de':      { name: 'Deutsch',            m: 'Thomas',  w: 'Sabine' },
    'fr':      { name: 'Français',           m: 'Philippe', w: 'Isabelle' },
    'es':      { name: 'Español',            m: 'Javier',  w: 'Marta' },
    'it':      { name: 'Italiano',           m: 'Roberto', w: 'Francesca' },
    'pt-BR':   { name: 'Português (Brasil)', m: 'Carlos',  w: 'Fernanda' },
    'nl':      { name: 'Nederlands',         m: 'Peter',   w: 'Marieke' },
    'pl':      { name: 'Polski',             m: 'Andrzej', w: 'Agnieszka' },
    'ja':      { name: '日本語',              m: '健一',     w: '美穂' },
    'ko':      { name: '한국어',              m: '성호',     w: '지영' },
    'zh-Hans': { name: '简体中文',            m: '建国',     w: '丽娜' },
  };

  // Each language's strings, from site/i18n/<lang>.js (loaded before this file).
  const T = window.DockFlipI18n || {};

  // Remember the English text the page was written with.
  const nodes = Array.from(document.querySelectorAll('[data-i18n]'));
  const EN = {};
  nodes.forEach(el => { EN[el.dataset.i18n] = el.innerHTML; });
  // Pictures' alt text, translated like the rest: <img data-i18n-alt="key" alt="English">.
  const pictures = Array.from(document.querySelectorAll('[data-i18n-alt]'));
  pictures.forEach(el => { EN[el.dataset.i18nAlt] = el.getAttribute('alt'); });

  function pick() {
    try {
      const q = new URLSearchParams(location.search).get('lang');
      if (q && LANGS[q]) return q;
    } catch (e) {}
    try {
      const saved = localStorage.getItem('dockflip-lang');
      if (saved && LANGS[saved]) return saved;
    } catch (e) {}
    const wanted = navigator.languages && navigator.languages.length ? navigator.languages : [navigator.language || 'en'];
    for (const tag of wanted) {
      const t = String(tag).toLowerCase();
      if (t.startsWith('zh')) return 'zh-Hans';
      if (t.startsWith('pt')) return 'pt-BR';
      if (t.startsWith('nb') || t.startsWith('nn') || t.startsWith('no')) return 'nb';
      const base = t.split('-')[0];
      if (LANGS[base]) return base;
    }
    return 'en';
  }

  function apply(lang) {
    const dict = T[lang] || {};
    const names = LANGS[lang] || LANGS.en;
    const fill = html => html.replace(/\{m\}/g, names.m).replace(/\{w\}/g, names.w);
    nodes.forEach(el => {
      const key = el.dataset.i18n;
      el.innerHTML = fill(dict[key] !== undefined ? dict[key] : EN[key]);
    });
    pictures.forEach(el => {
      const key = el.dataset.i18nAlt;
      el.setAttribute('alt', dict[key] !== undefined ? dict[key] : EN[key]);
    });
    // Initials in the two avatar circles.
    const faces = document.querySelectorAll('.person .face');
    if (faces[0]) faces[0].textContent = Array.from(names.m)[0];
    if (faces[1]) faces[1].textContent = Array.from(names.w)[0];
    document.documentElement.lang = lang;
    if (dict['meta.title']) document.title = dict['meta.title'];
    const select = document.getElementById('lang');
    if (select) select.value = lang;
  }

  // A page that scripts/build-site.mjs already wrote in one language (/fi/ and
  // so on, for search engines) keeps that language: its text is not English,
  // so swapping in place would mix languages. Choosing another one goes to
  // that language's page instead.
  // The English root page that build-site.mjs wrote is marked data-pages: the
  // other languages have their own pages beside it, so it goes there too and
  // the address can be shared. site/index.html opened as it is has no
  // such pages, and swaps text in place.
  const fixed = document.documentElement.dataset.lang;
  const pages = fixed || document.documentElement.hasAttribute('data-pages');
  const urlOf = code => (fixed ? '../' : './') + (code === 'en' ? '' : code + '/');

  const select = document.getElementById('lang');
  if (select) {
    Object.entries(LANGS).forEach(([code, l]) => {
      const o = document.createElement('option');
      o.value = code; o.textContent = l.name;
      select.appendChild(o);
    });
    select.addEventListener('change', () => {
      try { localStorage.setItem('dockflip-lang', select.value); } catch (e) {}
      if (pages) location.href = urlOf(select.value);
      else apply(select.value);
    });
  }
  if (fixed) { if (select) select.value = fixed; }
  else apply(pick());
})();
