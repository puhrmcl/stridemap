# Northwest Ag Technologies — logo assets

Vector traced from the supplied transparent PNG (1641 x 403) with potrace, then
split into two colour layers. The traced outlines match the source; these replace
the bitmaps that were previously cropped out of the brand sheet.

Two colours only:

| | HEX | use |
|---|---|---|
| Green | `#386E0D` | the field-and-furrow icon |
| Charcoal | `#1C1C1B` | the wordmark |

Note: the brand sheet lists charcoal as `#3F403E`. The supplied lockup uses
`#1C1C1B`, which is markedly darker. `#1C1C1B` is used here because it came from the
artwork; confirm which is canonical.

    lockup.svg           icon + wordmark, brand colours
    lockup-reversed.svg  on a charcoal field, for dark grounds
    lockup-mono.svg      one colour, inherits currentColor
    icon.svg             icon alone
    icon-mono.svg        icon alone, inherits currentColor
    wordmark.svg         wordmark alone

Typeface is Norwester Bold Italic. It is not on the Google Fonts CDN, so any web
build must self-host the file; the logo files above are outlines and need no font.
