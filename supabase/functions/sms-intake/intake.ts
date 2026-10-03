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

/** The reply to the resident (one SMS). */
export function ackMessage(incidentId: string, known: boolean): string {
  return known
    ? `S.A.G.I.P.: Your SOS was received (${incidentId}). MDRRMD is on it. Stay safe and keep your phone on.`
    : `S.A.G.I.P.: Your SOS was received (${incidentId}). MDRRMD will call this number to confirm. Stay safe.`;
}

/** The reply when a text could not be read. */
export function unreadableMessage(): string {
  return "S.A.G.I.P.: We could not read this message. For rescue, hold SOS in the S.A.G.I.P. app or call MDRRMD.";
}

/**
 * The gateway sends the shared secret as `Authorization: Bearer <secret>`
 * or `x-sagip-key: <secret>`. Compared in constant time.
 */
export function authorized(
  headers: { get(name: string): string | null },
  secret: string,
): boolean {
  const bearer = headers.get("authorization")?.replace(/^Bearer\s+/i, "") ?? null;
  const given = headers.get("x-sagip-key") ?? bearer;
  if (!given || given.length !== secret.length) return false;
  let diff = 0;
  for (let i = 0; i < secret.length; i++) {
    diff |= given.charCodeAt(i) ^ secret.charCodeAt(i);
  }
  return diff === 0;
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
 * when none is left.
 */
export function gatewaySendRequest(
  url: string,
  username: string,
  password: string,
  to: string | string[],
  text: string,
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
        ttl: 3600,
      }),
    },
  };
}
