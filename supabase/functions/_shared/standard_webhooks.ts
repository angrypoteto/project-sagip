// Verifies Standard Webhooks signatures, which Supabase Auth hooks use
// (https://www.standardwebhooks.com). Web Crypto only, so it runs in the
// Edge Function (Deno) and in the Node tests.

/** How far the hook's timestamp may be from now, in seconds. */
export const toleranceSeconds = 5 * 60;

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function bytesToBase64(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin);
}

/** The secret as Supabase shows it: `v1,whsec_<base64>`. */
function secretBytes(secret: string): Uint8Array {
  const raw = secret.replace(/^v1,/, "").replace(/^whsec_/, "");
  return base64ToBytes(raw);
}

export async function sign(
  secret: string,
  id: string,
  timestamp: string,
  body: string,
): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    // A copy on a plain ArrayBuffer, as newer TypeScript DOM types require.
    new Uint8Array(secretBytes(secret)),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${id}.${timestamp}.${body}`),
  );
  return bytesToBase64(new Uint8Array(mac));
}

/** Constant-time comparison, so the check does not leak the signature. */
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/**
 * True when the request came from Supabase Auth: the `webhook-signature`
 * header holds a valid HMAC of the id, timestamp, and body, and the
 * timestamp is recent.
 */
export async function verifyWebhook(
  secret: string,
  body: string,
  headers: { get(name: string): string | null },
  nowSeconds: number = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  const id = headers.get("webhook-id");
  const timestamp = headers.get("webhook-timestamp");
  const signatures = headers.get("webhook-signature");
  if (!id || !timestamp || !signatures) return false;
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(nowSeconds - ts) > toleranceSeconds) {
    return false;
  }
  const expected = await sign(secret, id, timestamp, body);
  return signatures
    .split(" ")
    .map((s) => s.replace(/^v1,/, ""))
    .some((s) => same(s, expected));
}
