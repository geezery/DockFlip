# Languages

DockFlip speaks 15 languages:

English · Suomi (Finnish) · Svenska (Swedish) · Dansk (Danish) · Norsk
(Norwegian) · Deutsch (German) · Français (French) · Español (Spanish) ·
Italiano (Italian) · Português do Brasil (Portuguese, Brazil) · Nederlands
(Dutch) · Polski (Polish) · 日本語 (Japanese) · 한국어 (Korean) · 简体中文
(Chinese, Simplified)

## Choosing one

DockFlip follows your macOS language. To use another one just for DockFlip, open
the menu bar menu → 🌐 **Language**.

## "Help, I picked a language I can't read"

It happens. The Language menu always shows 🌐 and the word "Language" in
English too, and every language is listed with its English name. Look for 🌐
and pick **English**.

From Terminal:

```sh
defaults delete io.github.dockflip.DockFlip AppleLanguages
```

Then restart DockFlip.

## Improving a translation

Translations live in `Resources/<language>.lproj/Localizable.strings`. If one
reads like it went through a machine twice, a pull request from a native
speaker is very welcome. See [CONTRIBUTING.md](https://github.com/geezery/DockFlip/blob/main/CONTRIBUTING.md).
