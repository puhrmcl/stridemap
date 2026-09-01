# Northwest Ag Technologies — App Platform Handbook

The "paved road" for building, hosting, documenting, and maintaining apps across the
portfolio. The goal is a **repeatable process**: each new app is stamped from a template,
follows the same conventions, and needs no bespoke decisions for the boring parts.

> This handbook should eventually live in the org-wide `.github` repo (see
> [§12](#12-repeatable-new-app-checklist)). It's kept here for now as the first reference copy.

---

## 1. Org facts (fill once, reuse everywhere)

| Thing | Value |
|---|---|
| Legal entity | **Northwest Ag Technologies, L.L.C.** |
| Copyright line | `© <year> Northwest Ag Technologies, L.L.C.` |
| GitHub owner | `puhrmcl` *(consider migrating to a `northwest-ag` org as the portfolio grows)* |
| Apple Developer Team ID | `UV4A75F95G` (Organization) |
| Root domain | `nwagtech.com` |
| Support / contact email | `software@nwagtech.com` |
| DNS / edge | Cloudflare |

---

## 2. App archetypes & default stacks

Pick the archetype, get the stack. Deviate only with a written reason.

### A) Native iOS (e.g. **Etch**)
- **UI:** SwiftUI, deployment target **iOS 18**.
- **Persistence:** SwiftData (on-device).
- **Auth/identity:** native (Sign in with Apple / HealthKit / none).
- **Backend:** none by default. If a secret must not ship in the app (OAuth exchange,
  API keys), add **one Cloudflare Worker** as a thin proxy — see Etch's `worker/`.
- **CI/CD:** **Xcode Cloud** (native App Store Connect integration, handles signing +
  TestFlight).
- **Legal/landing pages:** `docs/` → GitHub Pages → mapped to a subdomain.

### B) Web / full-stack (e.g. **NestEgg**)
- **Frontend:** Next.js on **Vercel** (preview deploy per PR, prod on `main`).
- **Auth:** **Clerk**.
- **Backend / long-running services + DB:** **Railway** (Postgres + services).
- **Light serverless / edge:** Vercel functions or a **Cloudflare Worker**.
- **CI/CD:** Vercel + Railway git-deploy (both build from GitHub automatically).

**One tool per job — keep lanes clean:**

| Job | Default |
|---|---|
| Web frontend + light serverless | Vercel |
| Stateful backend + Postgres | Railway |
| Auth (web) | Clerk |
| Edge / secret proxy | Cloudflare Workers |
| iOS build & release | Xcode Cloud |
| DNS + domains | Cloudflare |
| Static legal/landing | GitHub Pages (`/docs`) |

---

## 3. Repositories

- **One repo per app**, one clear name (`etch`, `nestegg`).
- Two **template repos** to bootstrap from ("Use this template"):
  - `template-ios` — Etch's shape (app + `docs/` + optional `worker/`).
  - `template-web` — NestEgg's shape (Next.js + Clerk + Railway + `docs/`).
- One **org `.github` repo** — shared issue/PR templates, reusable Actions workflows,
  org profile README, and this handbook.

### Standard repo layout
```
README.md                 # what it is, stack, setup, run
PLATFORM.md               # (symlink/reference to org handbook, optional)
CHANGELOG.md              # Keep a Changelog format, SemVer
.env.example              # every env var, no values
.gitignore
CLAUDE.md / AGENTS.md     # conventions for AI agents working in the repo
docs/
  index.html              # landing + support page  → Support URL
  privacy.html / .md      # privacy policy          → Privacy URL
  architecture.md         # how it's wired
  app-store-metadata.md   # (iOS) listing copy       or  deploy.md (web)
```

---

## 4. The "golden doc set" (documentation standard)

Every app ships these, always, so docs are never an afterthought:

1. **README** — one-paragraph pitch, stack, local setup, how to run, how to deploy.
2. **docs/privacy.{html,md}** — privacy policy (theme-aware HTML for hosting + Markdown).
3. **docs/index.html** — landing + support page (satisfies Apple's Support URL and gives
   web apps a marketing page).
4. **docs/architecture.md** — data model, services, external dependencies, diagrams.
5. **CHANGELOG.md** — every release, human-readable.
6. **.env.example** — the contract for configuration.
7. **CLAUDE.md / AGENTS.md** — repo conventions so agent-assisted work stays consistent.

Etch already carries 1–3, 6 (and `app-store-metadata.md`); it's effectively the
seed for `template-ios`.

---

## 5. Secrets & configuration

- **Never in git.** `.env.example` documents *names only*; real values live in the host
  (Vercel / Railway / Cloudflare Worker secrets / Xcode Cloud env).
- Naming convention: `APP_SERVICE_KEY` (e.g. `NESTEGG_CLERK_SECRET_KEY`).
- Optional single source of truth as you scale: **Doppler** or **1Password**, synced into
  each host.
- iOS: public IDs (Client ID, Team ID) may ship in the app; **secrets go in a Worker**,
  never the bundle (Etch's Strava proxy is the pattern).

---

## 6. Domains & URLs

Point `nwagtech.com` at Cloudflare and give each app a subdomain — portable, branded, and
it fixes the Apple Privacy/Support URL story permanently:

| App | Site | Privacy | Support |
|---|---|---|---|
| Etch | `etch.nwagtech.com` | `/privacy` | `/` (or `/support`) |
| NestEgg | `nestegg.nwagtech.com` | `/privacy` | `/support` |

GitHub Pages and Vercel both accept custom domains, so switching hosts later never breaks
a published URL. Until DNS is set up, GitHub Pages defaults to
`https://puhrmcl.github.io/<repo>/`.

---

## 7. CI/CD

- **Web:** Vercel builds every PR (preview URL) and deploys `main` to production; Railway
  auto-deploys its services from GitHub. No custom pipeline needed for the common case.
- **iOS:** **Xcode Cloud** — connect the repo, one workflow builds on push, runs tests,
  and ships to TestFlight. It manages signing with the org Team ID (`UV4A75F95G`).
- **Shared checks:** reusable GitHub Actions in the `.github` repo for lint/test on PR.
- **Dependencies:** Dependabot or Renovate enabled org-wide.

---

## 8. Versioning & releases

- **SemVer** everywhere; iOS `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` track it.
- Every user-facing release updates `CHANGELOG.md` and the store "What's New".
- Tag releases (`v1.2.0`); let the host deploy from the tag or `main`.

---

## 9. Legal & compliance defaults

- Privacy policy required for every published app (App Store **and** any web app that
  touches user data). Use the `docs/privacy` template; tailor the "what we access" section.
- iOS App Privacy labels: default to **"Data Not Collected"** for on-device apps; revisit
  the moment you add analytics, crash reporting, or server sync.
- HealthKit apps: never use Health data for advertising or share it with third parties;
  include HealthKit-specific reviewer notes (see Etch's `app-store-metadata.md`).

---

## 10. Maintenance rhythm

- **Monthly:** merge Dependabot PRs; check host dashboards (Vercel/Railway/Cloudflare) for
  errors and usage.
- **Per OS release (iOS):** rebuild on the new Xcode, test, ship a compatibility update.
- **Portfolio dashboard:** the org profile README lists each app, its status, and links to
  its site/privacy/repo.

---

## 11. Cost posture (solo-portfolio friendly)

Every default has a usable free tier at portfolio scale: Vercel Hobby, Railway starter,
Cloudflare Workers free, Clerk free tier, GitHub Free, Cloudflare DNS. The only fixed cost
is the **Apple Developer Program ($99/yr)**. Watch Railway usage (the one that meters
compute/DB) as apps get real traffic.

---

## 12. Repeatable new-app checklist

1. **Create repo** from `template-ios` or `template-web`.
2. Rename/replace app identifiers; set `.env.example`.
3. **Docs:** fill `README`, `docs/privacy`, `docs/index.html`, `docs/architecture.md`.
4. **Domain:** add `app.nwagtech.com` in Cloudflare → point at Pages/Vercel.
5. **Hosting:** connect Vercel + Railway (web) **or** Xcode Cloud (iOS).
6. **Secrets:** add real values in the host; never commit them.
7. **Legal:** privacy URL + support URL resolve; App Privacy labels answered.
8. **CI:** confirm PR checks + auto-deploy are green.
9. **Release:** tag `v1.0.0`, update `CHANGELOG`, ship to TestFlight / prod.
10. **Register** the app in the org portfolio README.

---

_Living document. Update it whenever a convention changes, and keep the canonical copy in
the org `.github` repo so every app inherits the same paved road._
