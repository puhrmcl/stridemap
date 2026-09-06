# Verde House — logo assets

A saguaro standing in a doorway, with the desert sun behind it. Wordmark in a
high-contrast display serif. Gilbert, Arizona. A subsidiary of Northwest Ag
Technologies, L.L.C.

These are **the supplied artwork, vectorised** — not a redraw.

## Files

    lockup-primary.svg        symbol + wordmark, brand colours
    lockup-primary-reversed   warm white on Verde green
    lockup-primary-black      one colour
    lockup-primary-mono       inherits currentColor
    lockup-horizontal.svg     composed: symbol left, wordmark right
    symbol.svg                arch, saguaro and sun
    wordmark.svg              type alone
    app-icon · avatar · favicon-32 · favicon-16

The horizontal lockup does not exist in the supplied artwork. It is composed from
the same two traced elements — symbol at full height, wordmark set at 46 % of it,
gap 16 % — because the site navigation needs a wide form.

## How these were made

The source was a PNG at 1448 × 1086 on an off-white ground. Ink was separated
from ground, then split into three layers by hue and position — arch and saguaro,
sun, wordmark — and each traced with potrace at 2× supersampling. The trace
matches the source; it scales and reverses, which the PNG did not.

If a native vector of this logo exists, use it instead. A trace of a raster is
faithful, not identical, and the serif's hairlines are where the difference
shows.

## Colour

    Verde Green   #3E4F38   rgb(62 79 56)     CMYK 68/45/76/32
    Terracotta    #B86F43   rgb(184 111 67)   CMYK 22/62/79/7
    Warm White    #F4F1E9   rgb(244 241 233)  CMYK 3/3/7/0
    Black         #131614   rgb(19 22 20)     CMYK 70/55/60/90
    Pure White    #FFFFFF

Terracotta is the sun and nothing else — it is one element, not a general accent.

Values are read off the artwork rather than chosen. This supersedes an earlier
decision that locked `#1A3925`; the supplied logo's green is the brand's green.
CMYK figures are press builds — proof before a run.

## Reproduction

The arch is a **3.8 %-of-height stroke** and the serif's hairlines are finer
still. Practical floors:

- **screen** — clean to about 32 px; 24 px and below the arch, saguaro and sun
  begin to merge
- **favicon** — 16 px is supplied and legible as a silhouette, not as three
  distinguishable elements
- **embroidery, deboss, laser** — the wordmark's hairlines are below what a
  stitch or a die will hold. Use the symbol alone, or have the wordmark redrawn
  with a thicker minimum stroke for those applications specifically

None of this is a fault of the trace; it is a property of the artwork. It only
matters where the artwork has to get small or get physical.

## Superseded

`tools/` still contains the generators for two earlier directions — a
three-pad prickly pear built from tangent circles, and a parametric redraw of
this arch. Neither ships. They are kept only because the geometry and the drawn
alphabets may be useful again.
