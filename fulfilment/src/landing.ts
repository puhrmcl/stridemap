/**
 * byetch.com — the app's front door.
 *
 * One page, served straight from the worker so the whole property lives in one place:
 * the map (hero), how it works in three steps, the Studio and the Year Book as proof,
 * and one install action. Point byetch.com at this worker (Cloudflare → Workers →
 * etch-fulfilment → Settings → Domains & Routes → add custom domain) and the site is up.
 *
 * The screenshots are the app's own CI captures (seeded data, light appearance),
 * embedded as JPEG so the page has zero external dependencies and one round trip.
 * APP_STORE_URL is a wrangler var: empty renders the honest "coming soon" state;
 * set it to the App Store link when the listing is live and redeploy.
 */

import { LANDING_HERO_JPG, LANDING_STUDIO_JPG, LANDING_BOOK_JPG } from "./landing-assets";
// The privacy policy, bundled as text (wrangler [rules]). Source of truth is
// docs/privacy.html — re-copy it here when the policy changes.
import PRIVACY_HTML from "./privacy.html";

export function servePrivacy(): Response {
  return new Response(PRIVACY_HTML, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}

export interface LandingEnv {
  /** App Store product URL (wrangler.toml [vars]); empty = show "coming soon". */
  APP_STORE_URL?: string;
}

const SITE_ASSETS: Record<string, string> = {
  "hero.jpg": LANDING_HERO_JPG,
  "studio.jpg": LANDING_STUDIO_JPG,
  "book.jpg": LANDING_BOOK_JPG,
};

export function serveSiteAsset(name: string): Response {
  const b64 = SITE_ASSETS[name];
  if (!b64) return new Response("not found", { status: 404 });
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  return new Response(bytes, {
    headers: {
      "Content-Type": "image/jpeg",
      "Cache-Control": "public, max-age=86400",
    },
  });
}

export function serveLanding(env: LandingEnv): Response {
  const appStoreURL = (env.APP_STORE_URL ?? "").trim();
  const cta = appStoreURL
    ? `<a class="cta" href="${appStoreURL}">
         <svg class="apple" viewBox="0 0 384 512" aria-hidden="true"><path fill="currentColor" d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z"/></svg>
         <span><small>Download on the</small>App Store</span>
       </a>`
    : `<span class="cta soon"><span><small>Coming soon to the</small>App Store</span></span>`;

  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Etch — Every mile, made physical</title>
<meta name="description" content="Etch draws every run, ride and hike you've ever recorded on one map — then turns them into prints, photo walls and year books, made and shipped to your door.">
<meta property="og:title" content="Etch — Every mile, made physical">
<meta property="og:description" content="Import your whole activity history. See it on one map. Turn it into something you can hang.">
<meta property="og:image" content="/site/hero.jpg">
<style>
  /* The Etch Brand System, verbatim from the app's Theme:
     ink #17212B · ink-deep #10181F · blue #4A8EAE · blue-lift #6FB2D1 ·
     canvas #F3F0E9 · gallery-white #FBFAF7 · graphite #4A5055 · mist #C9CDCE.
     The page commits to the ink world — the app's light screens are the color. */
  :root {
    --ink: #17212B; --ink-deep: #10181F; --ink-well: #0B1116;
    --blue: #4A8EAE; --blue-lift: #6FB2D1; --blue-text: #8AC3DE;
    --bone: #F3F0E9; --white: #FBFAF7; --mist: #C9CDCE;
    --muted: rgba(243, 240, 233, 0.62);
    --hairline: rgba(243, 240, 233, 0.14);
  }
  * { box-sizing: border-box; margin: 0; }
  html { -webkit-text-size-adjust: 100%; scroll-behavior: smooth; }
  @media (prefers-reduced-motion: reduce) { html { scroll-behavior: auto; } }
  body {
    background: var(--ink-deep); color: var(--bone);
    font: 17px/1.6 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
  }
  a { color: inherit; text-decoration: none; }
  img { max-width: 100%; display: block; }

  .shell { max-width: 1060px; margin: 0 auto; padding: 0 24px; }

  /* ── Nav: just the mark. */
  nav { padding: 28px 0 0; display: flex; justify-content: space-between; align-items: baseline; }
  .mark { font-size: 26px; font-weight: 700; letter-spacing: -0.02em; color: var(--white); }
  .mark b { color: var(--blue-lift); font-weight: 700; }
  nav .navline { font-size: 13px; letter-spacing: 0.14em; color: var(--muted); text-transform: uppercase; }

  /* ── Hero */
  header { padding: 72px 0 40px; display: grid; grid-template-columns: 1.15fr 0.85fr; gap: 48px; align-items: center; }
  .eyebrow { font-size: 13px; font-weight: 600; letter-spacing: 0.22em; color: var(--blue-lift); text-transform: uppercase; margin-bottom: 22px; }
  .eyebrow::before { content: ""; display: block; width: 44px; height: 2px; background: var(--blue); margin-bottom: 14px; }
  h1 {
    font-size: clamp(44px, 7vw, 76px); line-height: 1.02; font-weight: 800;
    letter-spacing: -0.035em; color: var(--white); text-wrap: balance;
  }
  h1 .accent { color: var(--blue-lift); }
  .lede { margin: 26px 0 34px; font-size: 19px; max-width: 34em; color: var(--muted); }

  .cta {
    display: inline-flex; align-items: center; gap: 12px;
    background: var(--white); color: var(--ink);
    padding: 13px 26px 13px 22px; border-radius: 999px;
    font-weight: 700; font-size: 19px; letter-spacing: -0.01em; line-height: 1.15;
    transition: transform 0.15s ease;
  }
  .cta:hover { transform: scale(1.03); }
  .cta small { display: block; font-size: 11px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: #6b7075; }
  .cta .apple { width: 26px; height: 34px; }
  .cta.soon { background: transparent; color: var(--bone); border: 1px solid var(--hairline); cursor: default; }
  .cta.soon small { color: var(--muted); }
  .under-cta { margin-top: 16px; font-size: 13px; color: var(--muted); letter-spacing: 0.02em; }

  /* The phone: a quiet frame, no gimmicks. */
  .device { justify-self: center; width: min(300px, 78vw); border-radius: 44px; padding: 10px;
            background: var(--ink-well); border: 1px solid rgba(243,240,233,0.1);
            box-shadow: 0 40px 90px rgba(0,0,0,0.55); }
  .device img { border-radius: 35px; }

  /* ── The three steps */
  .steps { border-top: 1px solid var(--hairline); padding: 72px 0; }
  .kicker { font-size: 13px; font-weight: 600; letter-spacing: 0.22em; color: var(--blue-lift); text-transform: uppercase; margin-bottom: 40px; }
  .stepgrid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 44px; }
  .step h3 { font-size: 24px; font-weight: 700; letter-spacing: -0.02em; color: var(--white); margin: 10px 0 10px; }
  .step .n { font-size: 13px; font-weight: 700; letter-spacing: 0.18em; color: var(--blue-lift); }
  .step p { font-size: 15.5px; color: var(--muted); }

  /* ── Proof: the Studio and the Book */
  .proof { border-top: 1px solid var(--hairline); padding: 72px 0; }
  .proofgrid { display: grid; grid-template-columns: 1fr 1fr; gap: 44px; margin-top: 8px; }
  .card { background: var(--ink); border: 1px solid var(--hairline); border-radius: 24px; overflow: hidden; }
  .card img { width: 100%; }
  .card .cap { padding: 22px 24px 26px; }
  .card h3 { font-size: 21px; font-weight: 700; letter-spacing: -0.02em; color: var(--white); margin-bottom: 6px; }
  .card p { font-size: 15px; color: var(--muted); }

  /* ── The quiet feature line */
  .features { border-top: 1px solid var(--hairline); padding: 44px 0 40px; text-align: center; }
  .features p { font-size: 14px; letter-spacing: 0.16em; text-transform: uppercase; color: var(--muted); }
  .features b { color: var(--bone); font-weight: 600; }

  /* ── Close */
  .close { border-top: 1px solid var(--hairline); padding: 88px 0 96px; text-align: center; }
  .close h2 { font-size: clamp(32px, 5vw, 52px); font-weight: 800; letter-spacing: -0.03em; color: var(--white); margin-bottom: 30px; text-wrap: balance; }

  footer { border-top: 1px solid var(--hairline); padding: 30px 0 44px;
           display: flex; justify-content: space-between; flex-wrap: wrap; gap: 12px;
           font-size: 13px; color: var(--muted); }
  footer a:hover { color: var(--bone); }
  footer .links { display: flex; gap: 22px; }

  @media (max-width: 780px) {
    header { grid-template-columns: 1fr; padding-top: 52px; text-align: left; }
    .device { justify-self: start; margin-top: 8px; }
    .stepgrid, .proofgrid { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>
<div class="shell">

  <nav>
    <span class="mark">etch<b>.</b></span>
    <span class="navline">Made from your miles</span>
  </nav>

  <header>
    <div>
      <p class="eyebrow">The App</p>
      <h1>Every mile you've ever moved.<br><span class="accent">Made physical.</span></h1>
      <p class="lede">Etch draws every run, ride, hike and walk you've ever recorded on one
      map — then turns any of it into museum-grade prints, photo walls and year books,
      made and shipped to your door.</p>
      ${cta}
      <p class="under-cta">Free to download · Your data stays on your phone</p>
    </div>
    <div class="device"><img src="/site/hero.jpg" width="598" height="1300"
      alt="The Etch map: years of activities clustered across the country"></div>
  </header>

  <section class="steps">
    <p class="kicker">How it works</p>
    <div class="stepgrid">
      <div class="step">
        <span class="n">01</span>
        <h3>Download Etch.</h3>
        <p>Free on iPhone. No account, no feed, no followers — this is between you and
        your miles.</p>
      </div>
      <div class="step">
        <span class="n">02</span>
        <h3>Import your history.</h3>
        <p>Your entire archive syncs from Apple Health in minutes — every activity you've
        ever recorded, drawn on one map. Your workouts never leave your phone.</p>
      </div>
      <div class="step">
        <span class="n">03</span>
        <h3>Make it real.</h3>
        <p>Design in the Studio and order in the app: map prints, photo walls, medal
        frames, the Year Book. Printed, framed and shipped to your door.</p>
      </div>
    </div>
  </section>

  <section class="proof">
    <p class="kicker">What you can make</p>
    <div class="proofgrid">
      <div class="card">
        <img src="/site/studio.jpg" alt="The Etch Studio: a map print being designed">
        <div class="cap">
          <h3>The Studio</h3>
          <p>Your routes as art — five layouts, six palettes, terrain and satellite
          editions, your name and bib if you want them. Every line was run, not drawn.</p>
        </div>
      </div>
      <div class="card">
        <img src="/site/book.jpg" alt="The Etch Year Book: a coffee-table book of one year in motion">
        <div class="cap">
          <h3>The Year Book</h3>
          <p>Your year as a coffee-table book: the marks, the map, every month, every
          race, every activity in the record. A story of your year in motion.</p>
        </div>
      </div>
    </div>
  </section>

  <section class="features">
    <p><b>One map of everything</b> · States &amp; cities · Race days ·
    <b>Photo walls</b> · Medal frames · <b>Gift cards</b></p>
  </section>

  <section class="close">
    <h2>Your miles already tell the story.<br>Etch makes it worth hanging.</h2>
    ${cta}
  </section>

  <footer>
    <span>© ${new Date().getFullYear()} Etch</span>
    <span class="links">
      <a href="/privacy">Privacy</a>
    </span>
  </footer>

</div>
</body>
</html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=3600",
    },
  });
}
