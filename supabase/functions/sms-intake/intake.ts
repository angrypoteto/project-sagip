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
