/**
 * Etch — the gift card as an Apple Wallet pass.
 *
 * A .pkpass is a signed zip: pass.json (the card), icons, a manifest of SHA-1 digests, and a
 * detached PKCS#7 signature over that manifest made with an Apple-issued Pass Type ID
 * certificate. This module builds one on demand around a gift card code the caller already
 * holds — the pass *carries* the code (QR + text), it doesn't mint value, so the endpoint needs
 * no auth: nothing comes out that the caller didn't put in.
 *
 * Who calls it: the app. The buyer pastes the code Shopify emailed them and shares the pass to
 * the recipient (Messages/AirDrop hand a .pkpass straight to Wallet); the recipient who
 * redeemed in-app adds the same pass to their own Wallet. Both directions, one endpoint.
 *
 * Five secrets switch it on (see the deploy workflow): the Pass Type ID certificate and its
 * private key (PEM), Apple's WWDR G4 intermediate (PEM), and the pass type / team identifiers.
 * Until they are set the endpoint answers 503 and the app says passes aren't switched on yet.
 */

import forge from "node-forge";
import { zipSync } from "fflate";

export interface PassEnv {
  PASS_CERT_PEM?: string;
  PASS_KEY_PEM?: string;
  PASS_WWDR_PEM?: string;
  PASS_TYPE_ID?: string;
  PASS_TEAM_ID?: string;
}

export function passConfigured(env: PassEnv): boolean {
  return Boolean(env.PASS_CERT_PEM && env.PASS_KEY_PEM && env.PASS_WWDR_PEM
                 && env.PASS_TYPE_ID && env.PASS_TEAM_ID);
}

/** POST /giftpass {code, amount?} → application/vnd.apple.pkpass */
export async function serveGiftPass(request: Request, env: PassEnv): Promise<Response> {
  if (!passConfigured(env)) {
    return json({ error: "Wallet passes are not configured yet." }, 503);
  }
  let body: { code?: string; amount?: string };
  try {
    body = await request.json();
  } catch {
    return json({ error: "Send JSON: {code, amount?}." }, 400);
  }
  const code = (body.code ?? "").replace(/[\s-]/g, "");
  if (!/^[A-Za-z0-9]{8,32}$/.test(code)) {
    return json({ error: "That doesn't look like a gift card code." }, 400);
  }
  const amount = (body.amount ?? "").trim().slice(0, 12);

  const pkpass = await buildPass(code, amount, env);
  return new Response(pkpass, {
    headers: {
      "Content-Type": "application/vnd.apple.pkpass",
      "Content-Disposition": 'attachment; filename="Etch Gift Card.pkpass"',
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

async function buildPass(code: string, amount: string, env: PassEnv): Promise<Uint8Array> {
  const pass = {
    formatVersion: 1,
    passTypeIdentifier: env.PASS_TYPE_ID,
    teamIdentifier: env.PASS_TEAM_ID,
    // Unique per issued pass, so re-creating one for the same code replaces nothing.
    serialNumber: crypto.randomUUID(),
    organizationName: "Etch",
    description: "Etch Gift Card",
    logoText: "Etch",
    foregroundColor: "rgb(243,240,233)",   // bone on ink — the brand's print palette
    backgroundColor: "rgb(23,33,43)",
    labelColor: "rgb(74,142,174)",         // Etch blue for the small labels
    barcodes: [{
      format: "PKBarcodeFormatQR",
      message: code,
      messageEncoding: "iso-8859-1",
      altText: code,
    }],
    storeCard: {
      primaryFields: amount
        ? [{ key: "amount", label: "GIFT CARD", value: amount }]
        : [{ key: "card", label: "GIFT CARD", value: "Etch" }],
      secondaryFields: [
        { key: "spend", label: "GOOD FOR", value: "Prints · frames · books" },
      ],
      auxiliaryFields: [
        { key: "redeem", label: "REDEEM", value: "In the Etch app — Bag → Gift Cards" },
      ],
      backFields: [
        { key: "code", label: "Code", value: code },
        { key: "how", label: "How to use it",
          value: "1. Download Etch from the App Store\n2. Sync your activities\n3. Bag → Gift Cards → Redeem, with the code above\n4. Your order is prepaid up to the card — you only pay any difference." },
        { key: "balance", label: "Balance",
          value: "The card's remaining balance is applied automatically at checkout and carries over between orders." },
      ],
    },
  };

  const files: Record<string, Uint8Array> = {
    "pass.json": new TextEncoder().encode(JSON.stringify(pass)),
    "icon.png": fromBase64(ICON_1X),
    "icon@2x.png": fromBase64(ICON_2X),
    "icon@3x.png": fromBase64(ICON_3X),
  };

  // The manifest lists every file's SHA-1 (Apple's spec digest for pkpass manifests).
  const manifest: Record<string, string> = {};
  for (const [name, data] of Object.entries(files)) {
    const digest = await crypto.subtle.digest("SHA-1", data as BufferSource);
    manifest[name] = [...new Uint8Array(digest)]
      .map((b) => b.toString(16).padStart(2, "0")).join("");
  }
  const manifestBytes = new TextEncoder().encode(JSON.stringify(manifest));
  files["manifest.json"] = manifestBytes;
  files["signature"] = sign(manifestBytes, env);

  return zipSync(files, { level: 6 });
}

/** Detached PKCS#7 over the manifest: pass cert + WWDR intermediate, SHA-256 signature. */
function sign(manifestBytes: Uint8Array, env: PassEnv): Uint8Array {
  const certificate = forge.pki.certificateFromPem(env.PASS_CERT_PEM!);
  const key = forge.pki.privateKeyFromPem(env.PASS_KEY_PEM!);
  const wwdr = forge.pki.certificateFromPem(env.PASS_WWDR_PEM!);

  const signed = forge.pkcs7.createSignedData();
  let manifestBinary = "";
  for (const byte of manifestBytes) manifestBinary += String.fromCharCode(byte);
  signed.content = forge.util.createBuffer(manifestBinary);
  signed.addCertificate(wwdr);
  signed.addCertificate(certificate);
  signed.addSigner({
    key: key as unknown as string,   // forge's types say string; it takes a key object
    certificate,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime },
    ],
  });
  signed.sign({ detached: true });

  const der = forge.asn1.toDer(signed.toAsn1()).getBytes();
  const out = new Uint8Array(der.length);
  for (let i = 0; i < der.length; i++) out[i] = der.charCodeAt(i);
  return out;
}

function fromBase64(b64: string): Uint8Array {
  const raw = atob(b64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status, headers: { "Content-Type": "application/json" },
  });
}

// The pass icons: the Etch mark in miniature — a bone route line with blue endpoints on ink —
// generated once at authoring time and embedded, because a Worker has no bundle of assets.
const ICON_1X = "iVBORw0KGgoAAAANSUhEUgAAAB0AAAAdCAIAAADZ8fBYAAAAoUlEQVR42mMUV9RmoAFgYqANGDV31FxkwEKetjvn90EYKoZOWBUwkpEv4IZCQPi8oxDG2cm1VAgHiEvhhjIwMBjnNpNvLsSxEENxBQK+8CUYgpSmB+TQRHYsZpgis7HHG1w/mqsxzSXTvXAj7pzfR7yhRIUD1cIX011kGM1EUmol3gL0eIOnbeTIpTQckDMMMnuklb+4Mg8ZgHG0/TAkzQUAu/o7s6e0TmcAAAAASUVORK5CYII=";
const ICON_2X = "iVBORw0KGgoAAAANSUhEUgAAADoAAAA6CAIAAABu2d1/AAABPElEQVR42u3ZMQ4CIRAFUJZ4B2sTO6uNpd1ewt7eI1h5BHt7L2FnabyAh7HYhBBAYGCWBf1TbMyG4vkzIBO75Woj2ikpmipwwQUXXHDBBRdccJnq/bo3wB2V+pNaXbHr+Tffuh9a6l1SzIXSDZr218f44Xk51ZXuuh+MBlBWIcT2eJ6Z64xWiXVrUCzLR5u2yXK5kVvEv4wqlmnKtLPTibP3lme3ycxc/eLI76P7/CcD7SAjHfXG4oROnWqrBVNksWZxDYEhTr7EsHFtgV/MHm16ukrgFE8ULU/v+jNmjJbA5T3ti6brxMW/rGX4KZCxzO8EW6w/eSvqV03nFmvT/xjcpztEE2oRXKFu+7fDbt5OCKerzyH2lFIX156Z/HMfttoPc0lTVBXpxk9RZarDP+7gggsuuOCCC25EfQC08nvxCczF/wAAAABJRU5ErkJggg==";
const ICON_3X = "iVBORw0KGgoAAAANSUhEUgAAAFcAAABXCAIAAAD+qk47AAAB1ElEQVR42u3aMW5CMQyAYYi4Q+dKbJ0QYzcu0b07R+jEEbqz9xJsHSsuwGE6VEKRHi9NXpw4Tv63gcTg7zmxE7N+en5ZDf84CFBAAQUUUEABBRRQQAEFFFBAAQUUUEABhVEVbtfL7XoZWsGPv4TFuv2b+Idhb3eHgRTCb17KwvbuKLU6nPUgRSB6qJT55WPTTbbvjyf/48/nx3Bd09v5O4xiUmEuEba7w7QuTAlSIUzmgm8xR5AE4WwlQqHGyYkHkLldJ/28xa7pHkCJk49sy1xKYRr2AojItWDsTFnuLBzZF0R2Da50tPEQixNhLtT4xqlGjVDJiKTeUeZkHRNn+JVq7QhiuRD5qitkhI0z5RyEbiIo9I4iBbU5hQWvMTLsaolQNhdiINTXQkGFewz5GWFAIbNANpIIlXbH+lHpKzyMOR5ChcwVXQ5WMqJqv/AvhJaUGyTOIgo5dW4K8feNIpDO7asfsDrBSnY2lRRJU0vDVV4O1IgBFNpvECX3hf3x5A/Fvt5fh8uF6dgvPCa08iTcvgYmn0kXvoZzITz8TfqzADUCBRRQ6EhBZDTcQy7kj4Y7WRGZo+Eeuib2BRRQQAEFFFBAAQUUeFBAAQUUUEABheDzCzcPuEfpWKTZAAAAAElFTkSuQmCC";
