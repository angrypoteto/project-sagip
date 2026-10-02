// Helpers for the send-alerts Edge Function. Pure functions, tested with
// Node (alerts.test.ts).

/** A delivery claimed from the database (claim_alert_deliveries()). */
export interface ClaimedDelivery {
  delivery_id: number;
  channel: "push" | "sms" | "facebook";
  alert: {
    alert_id: string;
    level: string;
    title: string;
    body: string;
    barangays: string[];
    ended: boolean;
  };
}

/** The outcome recorded with finish_alert_delivery(). */
export interface Outcome {
  status: "sent" | "failed" | "notSetUp" | "ended";
  recipients: number | null;
  delivered: number | null;
  failed: number | null;
  detail: string | null;
}

const smsLimit = 160;

/**
 * The alert as one SMS: "S.A.G.I.P.: <title>. <body>", cut at a word to fit
 * 160 characters, so every alert costs one credit per resident.
 */
export function alertSmsText(title: string, body: string): string {
  const head = `S.A.G.I.P.: ${title.trim().replace(/[.!?]+$/, "")}.`;
  const full = `${head} ${body.trim()}`.replace(/\s+/g, " ");
  if (full.length <= smsLimit) return full;
  if (head.length >= smsLimit) return `${head.slice(0, smsLimit - 1).trimEnd()}…`;
  const room = full.slice(0, smsLimit - 1);
  const cut = room.lastIndexOf(" ");
  // Never cut inside the title.
  const kept = cut >= head.length ? room.slice(0, cut) : head;
  return `${kept.replace(/[,;:]$/, "")}…`;
}

/** Unique numbers in Semaphore's local form; anything else is dropped. */
export function cleanNumbers(
  numbers: string[],
  toLocal: (n: string) => string | null,
): string[] {
  const seen = new Set<string>();
  for (const n of numbers) {
    const local = toLocal(n);
    if (local) seen.add(local);
  }
  return [...seen].sort();
}

/**
 * Applies the daily cap: who gets the text now, and how many are left
 * out because the day's limit is reached.
 */
export function planBroadcast(
  numbers: string[],
  left: number,
): { send: string[]; overCap: number } {
  const room = Math.max(0, Math.floor(left));
  return { send: numbers.slice(0, room), overCap: Math.max(0, numbers.length - room) };
}

/** Semaphore takes up to 1,000 numbers per call. */
export function chunk<T>(items: T[], size = 1000): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * How many of a batch Semaphore accepted. Its messages endpoint answers
 * with one entry per recipient; an entry counts unless it says it failed.
 * Anything else (an error object, a non-2xx status) counts the whole
 * batch as failed.
 */
export function acceptedCount(httpOk: boolean, body: unknown, batchSize: number): number {
  if (!httpOk || !Array.isArray(body)) return 0;
  let ok = 0;
  for (const entry of body) {
    const status = typeof entry === "object" && entry !== null
      ? String((entry as Record<string, unknown>).status ?? "")
      : "";
    if (!/^(failed|refunded)$/i.test(status)) ok++;
  }
  return Math.min(ok, batchSize);
}

/** The delivery's outcome from the totals. */
export function smsOutcome(
  recipients: number,
  accepted: number,
  overCap: number,
): Outcome {
  const notSent = recipients - accepted;
  const notes: string[] = [];
  if (overCap > 0) notes.push(`${overCap} not sent: the daily limit was reached`);
  if (recipients === 0) notes.push("No registered residents in the affected barangays");
  return {
    // Nobody to text is not a failure.
    status: accepted > 0 || recipients === 0 ? "sent" : "failed",
    recipients,
    delivered: accepted,
    failed: notSent,
    detail: notes.length > 0 ? notes.join(". ") : null,
  };
}

/** Why a channel with no provider was not sent. */
export function notSetUp(channel: string): Outcome {
  const why = channel === "push"
    ? "Push needs the Firebase project"
    : channel === "facebook"
    ? "Facebook posting needs the page's access token"
    : "No Semaphore key";
  return { status: "notSetUp", recipients: null, delivered: null, failed: null, detail: why };
}

/** A rescue confirmation claimed from the database (claim_rescue_confirmations()). */
export interface ClaimedConfirmation {
  confirmation_id: number;
  incident_id: string;
  kind: "assigned" | "onScene" | "resolved";
  unit_call_sign: string | null;
  /** The resident's number as stored; full, so never logged. */
  to: string | null;
}

/**
 * What a resident is texted about their own SOS (FR6): one SMS, with the
 * incident number so they can quote it on the hotline. Only "assigned" is
 * queued today; the other two are worded for when that changes.
 */
export function confirmationSmsText(c: ClaimedConfirmation): string {
  const team = c.unit_call_sign?.trim() ? `Rescue team ${c.unit_call_sign.trim()}` : "A rescue team";
  switch (c.kind) {
    case "assigned":
      return `S.A.G.I.P.: ${team} has been sent to your location. Stay where you are if it is safe and keep your phone on. Ref ${c.incident_id}.`;
    case "onScene":
      return `S.A.G.I.P.: ${team} has arrived at your location. Ref ${c.incident_id}.`;
    case "resolved":
      return `S.A.G.I.P.: Your SOS ${c.incident_id} has been closed. If you still need help, send a new SOS or call MDRRMD.`;
  }
}

/** The outcome of one rescue text, recorded with finish_rescue_confirmation(). */
export interface ConfirmationOutcome {
  status: "sent" | "failed" | "notSetUp";
  detail: string | null;
}

export const ended: Outcome = {
  status: "ended",
  recipients: null,
  delivered: null,
  failed: null,
  detail: "The alert ended before it was sent",
};
