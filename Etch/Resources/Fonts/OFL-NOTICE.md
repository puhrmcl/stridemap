# Bundled fonts — licence notice

The three typefaces in this folder are licensed under the **SIL Open Font
License, Version 1.1**, which permits bundling them in an application and
serving them on the web, including commercially, provided they are not sold
on their own and the copyright notices below travel with them.

| Family | Copyright |
|---|---|
| **Inter** | Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter) |
| **Inter Tight** | Copyright (c) 2016 The Inter Project Authors (https://github.com/rsms/inter) |
| **Newsreader** | Copyright (c) 2019 The Newsreader Project Authors (https://github.com/productiontype/Newsreader) |

Full licence text: <https://openfontlicense.org/open-font-license-official-text/>

## Files

Static instances, one per weight, taken from Google Fonts. Weights are
separate files rather than one variable font on purpose: each Google static
instance carries the weight in its *family* name ("Inter SemiBold"), so
asking CoreText to switch weight within a family finds nothing and draws a
synthetic bold instead. `Etch/Design/Typography.swift` therefore names a
PostScript name per weight, and no branded font in the app is sent through
`.weight()`.

| File | PostScript name |
|---|---|
| `Inter-Light.ttf` | `Inter-Light` |
| `Inter-Regular.ttf` | `Inter-Regular` |
| `Inter-Medium.ttf` | `Inter-Medium` |
| `Inter-SemiBold.ttf` | `Inter-SemiBold` |
| `InterTight-Regular.ttf` | `InterTight-Regular` |
| `InterTight-Medium.ttf` | `InterTight-Medium` |
| `InterTight-SemiBold.ttf` | `InterTight-SemiBold` |
| `Newsreader-Regular.ttf` | `Newsreader16pt16pt-Regular` |
| `Newsreader-Medium.ttf` | `Newsreader16pt16pt-Medium` |
| `Newsreader-SemiBold.ttf` | `Newsreader16pt16pt-SemiBold` |

Newsreader's PostScript names carry Google's optical-size instance naming.
They are read from the shipped files' name tables, not guessed — no one would
arrive at `Newsreader16pt16pt-Regular` by reasoning about it, and a wrong name
fails silently by falling back to the system face.

Each file must also be listed under `UIAppFonts` in `Etch/Info.plist`, or it
ships in the bundle and never registers.

The storefront serves the **variable** builds of the same three families
(`storefront/assets/*-Variable.woff2`) — one file per family covering the whole
weight range, declared in `layout/theme.liquid` where `asset_url` can resolve
them.
