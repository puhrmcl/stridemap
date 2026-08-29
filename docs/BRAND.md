# Etch — Brand Reference

Source of truth for Etch's visual identity, from the Etch Brand System (v1).
Reference when theming the app, building the storefront, making App Store
assets, or designing new UI.

This document describes intent. The implementations are
`Etch/Design/Theme.swift` (colour), `Etch/Design/Typography.swift` (type) and
`storefront/assets/etch-tokens.css` (both, for the web). They hold the same
names in the same order; if this file and one of them disagree, the code is
what ships and this file is the bug.

## Essence

> Etch is the home for every run, ride, hike, race, and achievement. We turn
> your movement into art, your progress into legacy, and your story into
> something worth remembering.

- **Wordmark:** `etch.` (lowercase, with the full stop — the dot is Etch Blue)
- **Line:** **Remember Everything. Etch It.**
- **Rally line:** *Your journey. Preserved. Your story. Elevated.*
- **Sign-off:** *Made to move. Made to last.*

## Colour palette

| Name | Hex | Role |
|------|-----|------|
| **Etch Ink** | `#17212B` | Primary brand colour — logo, headers, dark UI |
| **Etch Blue** | `#4A8EAE` | Signature accent. Interaction and focus, sparingly |
| **Warm Canvas** | `#F3F0E9` | Primary light background |
| **Gallery White** | `#FBFAF7` | Cards, surfaces, print grounds, elevated moments |
| **Graphite** | `#4A5055` | Secondary text, icons, subtle UI elements |
| **Mist** | `#C9CDCE` | Dividers, inactive states, borders, map UI |

**The balance is the brand.** Roughly 65–70% warm neutrals, 20–25% Etch Ink,
3–5% Etch Blue. Blue marks what is live — selection, focus, the route itself.
Etch is not a blue interface, and a screen that has become one has drifted.

### Derived tones

The six above cannot express a two-appearance interface on their own. The
tokens add a small, named set, each justified where it is defined: `inkDeep`
and `inkWell` (dark grounds beneath Ink surfaces), `canvasSunken` (the same
job in light), `blueLift` (Etch Blue on dark), `blueFill` and `blueText`
(below), `graphiteLight`, `mistDeep`.

### Accessibility

Etch Blue is `3.53:1` on Gallery White. That clears the 3:1 that non-text UI
needs and falls short of the 4.5:1 that text needs, so there are three blues
rather than one:

- `accent` — `#4A8EAE`, for icons, strokes, selection marks, the route.
- `accentFill` — `#3D7B99`, for a solid control carrying a label (4.52:1).
- `accentText` — `#35708B`, for blue text on Warm Canvas (4.86:1).

Dark mode lifts to `#6FB2D1` (6.8:1 on Etch Ink) and `#8AC3DE` for text.

### Light and dark

Dark is designed, not inverted. The ground deepens out of Etch Ink rather
than the canvas flipping, and type stays warm — Warm Canvas on ink, never
white on black.

The app follows the phone. The storefront does not: appearance there is a
merchant choice made per section, so the dark token set rides Dawn's colour
schemes 3 and 4 rather than `prefers-color-scheme`.

## Typography

| Role | Face | Weights |
|------|------|---------|
| Display, headlines, nav, buttons, body, labels, UI | **Neue Haas Grotesk** | 45 Light · 55 Roman · 65 Medium · 75 Bold |
| Editorial moments | **Tiempos Text** | Regular · Medium · Semibold |
| iOS system UI where native type is preferable | **SF Pro** | — |

- **Tabular figures** for distance, pace, time, elevation, dates, totals,
  coordinates and achievement statistics. Always.
- **Sentence case** for most UI. The one deliberate uppercase is the small
  tracked metadata label (`PHOENIX, ARIZONA`).
- Avoid: excessive bold, excessive uppercase, sporty or condensed faces,
  generic SaaS styling. **No rounded type anywhere** — it was the app's old
  default and it is the one thing the brand rules out.

### Licensing — open

Neue Haas Grotesk is Monotype; Tiempos Text is Klim. Both are commercial, and
neither ships with iOS nor lives in this repo. **Licences covering app
embedding and web use need buying, and the files supplying.**

Until they arrive the tokens resolve to SF Pro and New York on iOS, and to
the platform grotesk and a Times-lineage serif on the web. Nothing looks
broken in the meantime, and nothing is blocked on the purchase:

- **iOS** — drop the `.otf` files into the target and list them under
  `UIAppFonts` in `Info.plist`. `EtchType` already asks for the branded family
  first and reports which state it is in via `EtchType.isBranded`.
- **Web** — drop the `.woff2` files into `storefront/assets/` and uncomment
  the `@font-face` block in `etch-tokens.css`. The stacks already name the
  licensed faces first.

No selector or call site changes on either surface.

## Icon system

Minimal line icons, thoughtful detail. Blue signals what is live. The app
icon is the wordmark in Gallery White on an Etch Ink ground, dot in Etch
Blue; the wordmark asset ships in an ink cut for light grounds and a paper
cut for dark.

## Tone of voice

Confident, not loud · Inspired, not gimmicky · Refined, not cluttered ·
Meaningful, not generic · Timeless, not trendy.

## Photography

Cinematic runners, roads, and landscapes at golden hour. Movement and place.

## Signature applications

- The map itself as the hero — clean, light, poster style, and **printed on
  the sheet rather than pasted onto it**: a map panel with its own ground
  colour leaves a seam, and the seam is what separates our prints from good
  ones.
- Route posters — a framed print of a single route with title, date and
  stats.
- Embossed mark on premium goods.

## Print artwork is not interface

`Theme.Artwork` is deliberately separate from the semantic tokens. A poster
is a product with its own paper and ink; it does not follow the phone into
dark mode, and the paper stocks offered to a customer (blueprint, rose,
topographic, Harbor's slate-navy) are catalogue choices rather than brand
colours. Interface code must never reach into `Artwork`, and artwork code
must never reach into `Surface` or `Ink`.
