// Helpers for the sms-intake Edge Function. Pure functions, tested with
// Node (sms_intake.test.ts).

/** An inbound SMS as the gateway forwards it. */
export interface InboundSms {
  from: string;
  text: string;
  receivedAt: string | null;
}

/**
 * Reads the gateway's webhook body. Two shapes are accepted:
 * - SMS Gateway for Android (capcom6): `{"event": "sms:received",
 *   "payload": {"message", "phoneNumber", "receivedAt"}}`
 * - a plain one for other gateways: `{"from", "text", "received_at"}`
 */
export function parseGatewayPayload(body: unknown): InboundSms | null {
  if (typeof body !== "object" || body === null) return null;
  const b = body as Record<string, unknown>;
  const p = (typeof b.payload === "object" && b.payload !== null)
    ? b.payload as Record<string, unknown>
    : null;
  if (p) {
    if (b.event !== undefined && b.event !== "sms:received") return null;
    const from = p.phoneNumber ?? p.sender;
    const text = p.message ?? p.text;
    if (typeof from !== "string" || typeof text !== "string") return null;
    return { from, text, receivedAt: typeof p.receivedAt === "string" ? p.receivedAt : null };
  }
  if (typeof b.from !== "string" || typeof b.text !== "string") return null;
  return {
    from: b.from,
    text: b.text,
    receivedAt: typeof b.received_at === "string" ? b.received_at : null,
  };
}

/**
 * The short code that ties a reply to the SOS it answers: the first 8 hex
 * characters of the SOS's own id. Only the sender's phone and the server
 * know that id, so a text faked from another number cannot pass as a
 * reply (2026-10-19). The app matches it (`SosSms.parseAck`).
 */
export function ackRef(clientId: string): string {
  return clientId.replaceAll("-", "").slice(0, 8).toLowerCase();
}

/** The reply to the resident (one SMS). The app reads it to stop asking nearby phones. */
export function ackMessage(incidentId: string, known: boolean, clientId: string): string {
  const id = `${incidentId}, ref ${ackRef(clientId)}`;
  return known
    ? `S.A.G.I.P.: Your SOS was received (${id}). MDRRMD is on it. Stay safe and keep your phone on.`
    : `S.A.G.I.P.: Your SOS was received (${id}). MDRRMD will call this number to confirm. Stay safe.`;
}

/** The reply when a text could not be read. */
export function unreadableMessage(): string {
  return "S.A.G.I.P.: We could not read this message. For rescue, hold SOS in the S.A.G.I.P. app or call MDRRMD.";
}

/**
 * A gateway that can add headers sends the shared secret as
 * `Authorization: Bearer <secret>` or `x-sagip-key: <secret>`. SMS Gateway
 * for Android signs instead ([signedByGateway]). Compared in constant time.
 */
export function authorized(
  headers: { get(name: string): string | null },
  secret: string,
): boolean {
  const bearer = headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? null;
  const given = headers.get("x-sagip-key") ?? bearer;
  return given !== null && same(given, secret);
}

/** Constant-time comparison, so a check does not leak the secret. */
function same(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** How far the gateway app's `X-Timestamp` may be from now, in seconds. */
export const signatureToleranceSeconds = 5 * 60;

/**
 * How SMS Gateway for Android signs each webhook (2026-10-20): the hex
 * HMAC-SHA256 of the raw body followed by the `X-Timestamp` value, keyed
 * with the app's Signing Key (Settings > Webhooks > Signing Key). The app
 * cannot send custom headers, so this is how it proves itself.
 */
export async function gatewaySignature(
  key: string,
  body: string,
  timestamp: string,
): Promise<string> {
  const k = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(body + timestamp));
  return [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/**
 * True when the webhook carries the gateway app's signature made with
 * [key] (the app's Signing Key, set to the same value as
 * SMS_INTAKE_SECRET), dated within [signatureToleranceSeconds] of [now] so
 * a captured request cannot be replayed later.
 */
export async function signedByGateway(
  headers: { get(name: string): string | null },
  body: string,
  key: string,
  now: number = Date.now() / 1000,
): Promise<boolean> {
  const signature = headers.get("x-signature")?.trim().toLowerCase();
  const timestamp = headers.get("x-timestamp")?.trim();
  if (!signature || !timestamp || !/^\d+$/.test(timestamp)) return false;
  if (Math.abs(now - Number(timestamp)) > signatureToleranceSeconds) return false;
  return same(signature, await gatewaySignature(key, body, timestamp));
}

/** A Philippine mobile number in E.164 ("+639171234567"), or null. */
export function e164(phone: string): string | null {
  let digits = phone.replace(/\D/g, "");
  if (digits.startsWith("63")) digits = digits.slice(2);
  if (digits.startsWith("0")) digits = digits.slice(1);
  if (digits.length !== 10 || !digits.startsWith("9")) return null;
  return `+63${digits}`;
}

/** The gateway phone's API (SMS Gateway for Android) from the secrets. */
export interface GatewayLogin {
  url: string;
  username: string;
  password: string;
}

/**
 * SMS_GATEWAY_SEND_URL, SMS_GATEWAY_USERNAME, and SMS_GATEWAY_PASSWORD, or
 * null when any is missing.
 */
export function gatewayLogin(get: (name: string) => string | undefined): GatewayLogin | null {
  const url = get("SMS_GATEWAY_SEND_URL");
  const username = get("SMS_GATEWAY_USERNAME");
  const password = get("SMS_GATEWAY_PASSWORD");
  return url && username && password ? { url, username, password } : null;
}

/**
 * The request that asks the gateway phone's app (SMS Gateway for Android,
 * cloud mode: https://api.sms-gate.app/3rdparty/v1/messages) to send a text
 * from the gateway SIM itself: the free alternative to Semaphore (the SIM's
 * own load or unlimited-text promo pays). High priority, so the app's rate
 * limit never holds back a reply to an SOS. [to] is one number or several;
 * numbers that are not Philippine mobiles are dropped, and null comes back
 * when none is left. [ttlSeconds] is how long the gateway keeps trying
 * before it gives up (an hour; a sign-in code passes its own expiry).
 */
export function gatewaySendRequest(
  url: string,
  username: string,
  password: string,
  to: string | string[],
  text: string,
  ttlSeconds = 3600,
): { url: string; init: RequestInit } | null {
  const numbers = [
    ...new Set((Array.isArray(to) ? to : [to]).map(e164).filter((n): n is string => n !== null)),
  ];
  if (numbers.length === 0) return null;
  return {
    url,
    init: {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${username}:${password}`)}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        textMessage: { text },
        phoneNumbers: numbers,
        priority: 100,
        ttl: ttlSeconds,
      }),
    },
  };
}

/** The thanks for a YES or NO to a dispatcher's SMS check. */
export function checkReplyThanks(incidentId: string, answer: "YES" | "NO"): string {
  return answer === "YES"
    ? `S.A.G.I.P.: Thank you. MDRRMD got your YES for ${incidentId}. Help is being arranged; keep your phone on.`
    : `S.A.G.I.P.: Thank you. MDRRMD got your NO for ${incidentId}. If you need help later, send a new SOS.`;
}
