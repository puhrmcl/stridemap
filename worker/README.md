# Etch — Strava token proxy (Cloudflare Worker)

A tiny Cloudflare Worker that performs Strava's OAuth token exchange and refresh so the
**client secret never ships inside the iOS app**. The app talks only to this Worker; the
Worker holds the secret and talks to Strava.

```
iPhone app ──(code / refresh_token)──▶  Worker  ──(+ client_secret)──▶  Strava
          ◀──────────── token JSON ─────────────────────────────────────┘
```

## Endpoints

| Method | Path            | Body                                                   |
|--------|-----------------|--------------------------------------------------------|
| `GET`  | `/health`       | —                                                      |
| `POST` | `/oauth/token`  | `{ "grant_type": "authorization_code", "code": "…" }`  |
| `POST` | `/oauth/token`  | `{ "grant_type": "refresh_token", "refresh_token": "…" }` |

The response is Strava's token JSON, passed straight through
(`access_token`, `refresh_token`, `expires_at`, and `athlete` on the initial exchange).

## Deploy (one time)

Prerequisites: a free [Cloudflare account](https://dash.cloudflare.com/sign-up) and Node 18+.

```bash
cd worker
npm install
npx wrangler login                       # opens the browser to authorize

# Store your Strava app credentials as Worker secrets (not committed anywhere):
npx wrangler secret put STRAVA_CLIENT_ID       # paste your Strava Client ID
npx wrangler secret put STRAVA_CLIENT_SECRET   # paste your Strava Client Secret

npx wrangler deploy
```

`wrangler deploy` prints the live URL, e.g.:

```
https://etch-strava-proxy.<your-subdomain>.workers.dev
```

## Wire up the app

Open `Etch/Config/StravaConfig.swift` and set:

```swift
static let clientID = "<your Strava Client ID>"     // public, safe in the app
static let tokenProxyURL = "https://etch-strava-proxy.<your-subdomain>.workers.dev"
```

That's it — there is **no `clientSecret` in the app anymore**. The Strava
"Authorization Callback Domain" stays `etch` (the app's URL scheme); the OAuth
redirect goes to the app, not to this Worker.

## Test

```bash
curl https://etch-strava-proxy.<your-subdomain>.workers.dev/health
# → {"ok":true}
```

## Security notes

- The secret lives only in Cloudflare (as an encrypted Worker secret) — never in the app
  bundle or in git.
- `/oauth/token` is public, but it is only useful to someone who already holds a valid,
  short-lived Strava `code` (obtained by completing OAuth for *your* client) or a user's
  `refresh_token` — both of which are themselves secrets. This is the standard mobile
  OAuth-proxy pattern.
- If you later want to harden against abuse, add an app-supplied header check or Cloudflare
  rate limiting / WAF rules. Left out here to keep the Worker minimal.
