# Etch — Brand Reference

Source of truth for Etch's visual identity, from the official brand brief.
Reference when theming the app, building marketing/App Store assets, or
designing new UI.

## Essence

> Etch is the visual record of an active life. We map the places you move, the
> miles you earn, and the moments that shape you. **You move in color. Your
> achievements become etched.**

- **Wordmark:** `etch` (lowercase)
- **Tagline:** **Leave your mark**
- **Rally line:** *Every mile. Every place. Etched forever.*
- **Pillars:** Record your journey · Reveal your story · Make it lasting

## Color palette (official)

| Name | Hex | RGB (0–1) | Role |
|------|-----|-----------|------|
| **Etch Ink** | `#101820` | 0.063, 0.094, 0.125 | Near-black ink — text, dark surfaces |
| **Etch Blue** | `#1473E6` | 0.078, 0.451, 0.902 | Primary/active accent — routes, pins, live, CTAs |
| **Bone** | `#F4F1EA` | 0.957, 0.945, 0.918 | Warm off-white — light background |
| **Stone** | `#D8D4CC` | 0.847, 0.831, 0.800 | Warm neutral — surfaces, map land |
| **Sage** | `#BBC8B2` | 0.733, 0.784, 0.698 | Muted green — greenspace, positive |
| **Mist** | `#DDE6EA` | 0.867, 0.902, 0.918 | Cool light grey-blue — map water, dividers |
| **Brass** | `#B08D57` | 0.690, 0.553, 0.341 | Warm metallic — achievements, premium accents |

Blue signals **activity / live experiences**. Bone/Stone/Sage/Mist are the
map-poster palette (the icon's map look). Brass is reserved for achievement
moments (PRs, milestones), used sparingly.

## Typography

- **Poppins SemiBold** — clean, modern, geometric.
- **Generous letter spacing** in headings and tags for a refined look.
- (App currently uses SF Pro Rounded; migrating headings/tags to Poppins is a
  tracked direction item — needs the Poppins font bundled, OFL-licensed.)

## Icon system

Minimal **line icons, rounded geometry**, thoughtful detail. Blue used to
signal activity/live. Reference marks: primary `e`, route (pin + path),
elevation (peaks), etch studio (framed map), achievement (medal).

## Tone of voice

Confident, not loud · Inspired, not gimmicky · Refined, not cluttered ·
Meaningful, not generic · Timeless, not trendy.

## Photography

Cinematic runners, roads, and landscapes at golden hour. Movement and place.

## Signature applications

- The map itself as the hero (clean, light poster style).
- **Route posters** — a framed print of a single route with title/date/stats
  (e.g. "Boston Marathon 04.15.24"). A natural share/export feature.
- Embossed `e` on premium goods (leather, etc.).

## Current app mapping / migration notes

`Etch/Design/Theme.swift` holds the in-app tokens.

- `Theme.accent` / `Theme.Route.recent` = **Etch Blue `#1473E6`** (aligned).
- Named palette tokens added: `Theme.Palette.ink / bone / stone / sage / mist /
  brass`.
- **Open direction items:** Poppins typography for headings/tags; a lighter,
  brand-tinted default map style (Bone/Stone/Sage/Mist) where MapKit allows;
  Brass accent on achievement/PR moments; a Route Poster export feature.
