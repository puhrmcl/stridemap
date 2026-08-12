# Etch — Brand Reference

Source of truth for Etch's visual identity. Reference when theming the app,
building marketing/App Store assets, or designing new UI.

## Wordmark & tagline

- **Wordmark:** `etch` (lowercase)
- **Tagline:** **Leave your mark**
- Wordmark color: Wordmark Navy (`#203A72`); may render in Etch Blue or white on dark.

Good candidates for reuse:
- App Store subtitle / promotional text: "Leave your mark."
- Onboarding hero, launch screen, empty-state.

## Color palette

| Name | Hex | RGB (0–1) | Role |
|------|-----|-----------|------|
| **Etch Blue** | `#1676F3` | 0.086, 0.463, 0.953 | Primary brand / accent — routes, pins, selected state, buttons |
| **Wordmark Navy** | `#203A72` | 0.125, 0.227, 0.447 | Wordmark, headings, deep-ink text |
| **Map Water** | `#5ABAF5` | 0.353, 0.729, 0.961 | Water on maps; light/secondary accent |
| **Map Green** | `#B6DF6C` | 0.714, 0.875, 0.424 | Parks/greenspace; positive/success |
| **Map Stone** | `#E8E2D6` | 0.910, 0.886, 0.839 | Landmass/buildings; warm neutral surface |
| **Background** | `#F6F6F4` | 0.965, 0.965, 0.957 | App background (light) |

## Current app mapping (as of this note)

`Etch/Design/Theme.swift` defines the in-app colors. Where they differ from
this kit today:

- `Theme.accent` / `Theme.Route.recent` = `#2D8AE1` (a slightly lighter,
  greener blue) — **not** the brand **Etch Blue `#1676F3`**. Aligning these
  would make routes/pins/selection match the icon and wordmark exactly.
- Route age gradient (`warm`/`mid`/`old`) is a blue→slate ramp, independent of
  this kit — fine to keep, or retune toward navy for the "old" end.
- Map base styling uses Apple Maps defaults; Map Water/Green/Stone here are the
  brand's own map look (used in the icon art), not currently applied to the
  live MapKit basemap.

To adopt the kit precisely, update `Theme.accent` (and `Route.recent`) to
`#1676F3` and add named tokens for Navy / Water / Green / Stone / Background.
