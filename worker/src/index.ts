/**
 * Etch — Strava OAuth token proxy (Cloudflare Worker)
 *
 * Strava's token exchange requires the app's `client_secret`. Shipping that secret
 * inside the iOS app is insecure, so this Worker holds it server-side and performs the
 * `authorization_code` exchange and `refresh_token` refresh on the app's behalf.
 *
 * The app sends only the public `client_id` (in the authorize URL) and, to this Worker,
 * the short-lived `code` or the user's `refresh_token`. The secret never leaves Cloudflare.
 *
 * Endpoints:
 *   GET  /health        → { ok: true }
 *   GET  /debug         → { hasClientId, clientIdLen, hasSecret, secretLen }
 *                         reports whether the env vars are visible to the Worker WITHOUT
 *                         revealing their values — used to diagnose `server_not_configured`.
 *   POST /oauth/token   → body: { grant_type, code? , refresh_token? }
 *                         proxies to Strava and returns Strava's token JSON verbatim.
 */

export interface Env {
  /** Strava application Client ID (set via `wrangler secret put STRAVA_CLIENT_ID`). */
  STRAVA_CLIENT_ID: string;
  /** Strava application Client Secret (set via `wrangler secret put STRAVA_CLIENT_SECRET`). */
  STRAVA_CLIENT_SECRET: string;
}

const STRAVA_TOKEN_URL = "https://www.strava.com/oauth/token";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method === "GET" && url.pathname === "/health") {
      return json({ ok: true });
    }

    // Reports whether the Strava credentials are visible to this Worker's runtime, without
    // ever exposing the secret's value. Lengths help catch a blank or space-padded value.
    if (request.method === "GET" && url.pathname === "/debug") {
      return json({
        hasClientId: !!env.STRAVA_CLIENT_ID,
        clientIdLen: (env.STRAVA_CLIENT_ID ?? "").length,
        hasSecret: !!env.STRAVA_CLIENT_SECRET,
        secretLen: (env.STRAVA_CLIENT_SECRET ?? "").length,
      });
    }

    if (url.pathname !== "/oauth/token") {
      return json({ error: "not_found" }, 404);
    }
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }

    if (!env.STRAVA_CLIENT_ID || !env.STRAVA_CLIENT_SECRET) {
      return json({ error: "server_not_configured" }, 500);
    }

    let body: Record<string, unknown>;
    try {
      body = (await request.json()) as Record<string, unknown>;
    } catch {
      return json({ error: "invalid_json" }, 400);
    }

    const grantType = body.grant_type;
    const params = new URLSearchParams();
    params.set("client_id", env.STRAVA_CLIENT_ID);
    params.set("client_secret", env.STRAVA_CLIENT_SECRET);

    if (grantType === "authorization_code") {
      const code = body.code;
      if (typeof code !== "string" || !code) {
        return json({ error: "missing_code" }, 400);
      }
      params.set("grant_type", "authorization_code");
      params.set("code", code);
    } else if (grantType === "refresh_token") {
      const refreshToken = body.refresh_token;
      if (typeof refreshToken !== "string" || !refreshToken) {
        return json({ error: "missing_refresh_token" }, 400);
      }
      params.set("grant_type", "refresh_token");
      params.set("refresh_token", refreshToken);
    } else {
      return json({ error: "unsupported_grant_type" }, 400);
    }

    const stravaResponse = await fetch(STRAVA_TOKEN_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: params.toString(),
    });

    // Pass Strava's JSON (and status) straight through to the app.
    const text = await stravaResponse.text();
    return new Response(text, {
      status: stravaResponse.status,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  },
};

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}
