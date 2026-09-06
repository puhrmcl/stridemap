# Ascend Imagery — logo assets

Aerial photography and imaging for real estate. Gilbert, Arizona. A subsidiary of
Northwest Ag Technologies, L.L.C. Formerly at ascendimg.com; that site is no
longer live.

These are the company's **existing** logo, not a redesign. A chevron symbol was
proposed and not adopted.

    wordmark.svg           vector trace, near-black #131614
    wordmark-mono.svg      same outlines, inherits currentColor
    wordmark-reversed.svg  warm white on Verde green
    wordmark.png           cut-out, transparent, 922 x 219
    wordmark-reversed.png  warm white cut-out

## How these were made, and what that means

The only source was a JPEG of the logo sitting on a sky gradient. The background
was estimated with a 121 px box blur and subtracted, small speckle discarded, and
the remaining alpha traced with potrace. The trace matches the source closely and
scales cleanly, which the JPEG did not.

It is still a trace of a compressed raster. **If the original vector exists, use
it instead** — the terminals of the script and the fine joins are where a trace
loses the most, and no amount of care recovers detail JPEG compression removed.

## The gap that remains

The identity is a wordmark and nothing else, at 4.9:1. It cannot fill a square,
so there is no artwork for:

- a circular profile picture (Facebook)
- an app tile or favicon
- a watermark in the corner of a listing photo

Below roughly 200 px wide the subtitle drops out, and the script's finest joins
measure 1 px on the full-size artwork, so they break rather than simply shrinking.
Whatever fills those slots later should be a companion to this wordmark, not a
replacement for it.
