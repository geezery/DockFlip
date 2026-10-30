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
    // Initials in the two avatar circles.
    const faces = document.querySelectorAll('.person .face');
    if (faces[0]) faces[0].textContent = Array.from(names.m)[0];
    if (faces[1]) faces[1].textContent = Array.from(names.w)[0];
    document.documentElement.lang = lang;
    if (dict['meta.title']) document.title = dict['meta.title'];
    const select = document.getElementById('lang');
    if (select) select.value = lang;
  }

  const select = document.getElementById('lang');
  if (select) {
    Object.entries(LANGS).forEach(([code, l]) => {
      const o = document.createElement('option');
      o.value = code; o.textContent = l.name;
      select.appendChild(o);
    });
    select.addEventListener('change', () => {
      try { localStorage.setItem('dockflip-lang', select.value); } catch (e) {}
      apply(select.value);
    });
  }
  apply(pick());
})();
