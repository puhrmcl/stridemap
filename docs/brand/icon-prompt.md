# Etch — image-generation prompts (ChatGPT / DALL·E, Midjourney, etc.)

Two prompts: **A** = the real App Store icon (tile only, no text — this is the file you ship).
**B** = the marketing hero (tile + wordmark, for the website / App Store screenshots).

Set the image size to **1:1 (square)**. Generate several; pick the cleanest. Then flatten to a
**1024×1024 PNG with no transparency** before dropping into `Etch/Assets.xcassets`.

---

## A) App icon (ship this — NO text)

> A premium iOS app icon, square 1:1, filling the entire frame edge to edge, with NO rounded
> corners and NO drop shadow (the operating system adds those). Absolutely no text, no letters,
> and no words anywhere in the image.
>
> Subject: a single continuous glowing running route, rendered as a thin neon ember line — warm
> orange (hex #fc5c44) with a brighter #ff8a5b inner glow and soft outer bloom — that loops
> elegantly to form the shape of a lowercase cursive letter "e". It looks like an illuminated GPS
> trace with rounded ends; a small bright dot marks the start point of the run.
>
> Background: a top-down aerial map of a quiet suburban neighborhood at night — dark charcoal
> streets, cul-de-sacs, and tiny rooftops — in near-black tones (around #0c0c0f), subtly
> embossed/engraved so the map reads as fine texture rather than clutter. Keep the map very low
> contrast so the glowing ember route is unmistakably the hero.
>
> Style: minimalist, high-end, cinematic, moody, Apple-caliber craftsmanship. The glowing route
> must be bold and high-contrast enough to stay instantly legible when the icon is scaled down to
> about 48×48 pixels. Centered composition with generous margins, soft realistic lighting on the
> ember line. No UI, no frames, no badges, no watermark, no border.

---

## B) Marketing hero (tile + wordmark — for web / screenshots, NOT the app icon)

> A high-end product shot of a single app icon, centered on a textured matte-black studio
> background. The icon is a rounded-square tile shown as a physical embossed object with a soft
> realistic drop shadow and subtle debossed edge. Inside the tile: a top-down near-black aerial
> map of a suburban neighborhood, engraved in dark charcoal, with one glowing neon ember running
> route (warm orange #fc5c44 with a brighter #ff8a5b glow) looping to form a lowercase cursive
> letter "e", with a bright dot at the route's start. Below the tile, the single lowercase word
> "etch" set in a clean geometric sans-serif, rendered in dark embossed/engraved metal that
> catches a faint warm rim light. Moody, premium, minimal, cinematic lighting. Square 1:1.

> ⚠️ Image generators frequently misspell text. For B, expect to redo the "etch" wordmark cleanly
> in a design tool (or overlay real vector type) rather than trusting the AI-rendered letters.

---

## Production checklist (turning the output into the shipped icon)

1. Use **A** for the icon. Crop to the **tile only** (no shadow, no background, no text).
2. Export **1024×1024 PNG, no alpha/transparency** (Apple rejects transparent icons).
3. Shrink a copy to ~48px and confirm the ember "e" still reads instantly. If it muddies,
   regenerate with "simpler map texture, bolder brighter route."
4. Match the app's in-app accent to the final icon hue (currently `#fc5c44`).
5. Drop into `Etch/Assets.xcassets/AppIcon.appiconset/` and point `Contents.json` at the file.
