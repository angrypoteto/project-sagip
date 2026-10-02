// send-alerts: works through queued alert deliveries (FR6, plan section 12).
//
// Each alert (from the threshold engine or MDRRMD) has one delivery row per
// channel. This function claims the queued ones and:
// - SMS: texts the registered residents of the affected barangays through
//   Semaphore, one SMS each, up to the daily cap set on A3
//   (channels.sms_daily_cap). Every text is kept in sms_log; the delivery
//   row gets the counts.
// - Push: sent through Firebase Cloud Messaging to topics: "manila" for an
//   alert for all of Manila, else the topics of its barangays (the app
//   subscribes each resident to both). Marked "not set up" without the
//   FIREBASE_SERVICE_ACCOUNT secret.
// - Facebook: marked "not set up" until the Facebook Page token exists.
// Simulated alerts never reach this function: their deliveries are logged
// as "simulated" when the alert is issued.
//
// It also sends rescue confirmations (FR6): the one text that tells a
// resident a unit was assigned to their SOS. These go first, one SMS each,
// and are not counted against the daily cap on alert texts.
//
// And the personal pushes in push_message: rescue confirmations to the
// resident's phones, new assignments to the phones of the unit's
// responders. Tokens FCM no longer knows are marked forgotten.
//
// Call it from a Database Webhook on INSERT into public.alert_delivery, on
// INSERT into public.rescue_confirmation, and on INSERT into
// public.push_message (or on a schedule) with the shared secret as
// `x-sagip-key`. A run with nothing queued does nothing, so extra calls
// are harmless.
//
// Secrets (Edge Functions > Secrets): ALERTS_SECRET, SEMAPHORE_API_KEY,
// optional SEMAPHORE_SENDER_NAME, FIREBASE_SERVICE_ACCOUNT (the whole JSON
// key file). SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by
// the platform.
//
// Deploy with JWT checking off (the webhook uses the shared secret):
//   supabase functions deploy send-alerts --no-verify-jwt

import { maskNumber, semaphoreNumber } from "../send-sms/sms.ts";
import { authorized } from "../sms-intake/intake.ts";
import {
  acceptedCount,
  alertSmsText,
  chunk,
  type ClaimedConfirmation,
  type ClaimedDelivery,
  cleanNumbers,
  type ConfirmationOutcome,
  confirmationSmsText,
  ended,
  notSetUp,
  type Outcome,
  planBroadcast,
  smsOutcome,
} from "./alerts.ts";
import {
  accessToken,
  alertTargets,
  channels,
  fcmMessage,
  parseServiceAccount,
  type ServiceAccount,
  sendMessage,
  type Target,
} from "./fcm.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function rest(path: string, body: unknown): Promise<Response> {
  return await fetch(`${url}/rest/v1/${path}`, {
    method: "POST",
    headers: {
      apikey: serviceKey!,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
}

async function rpc<T>(name: string, params: Record<string, unknown> = {}): Promise<T> {
  const res = await rest(`rpc/${name}`, params);
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

async function finish(d: ClaimedDelivery, o: Outcome): Promise<void> {
  await rpc("finish_alert_delivery", {
    p_delivery_id: d.delivery_id,
    p_status: o.status,
    p_recipients: o.recipients,
    p_delivered: o.delivered,
    p_failed: o.failed,
    p_detail: o.detail,
  });
}

async function sendSms(d: ClaimedDelivery, apiKey: string): Promise<Outcome> {
  const numbers = cleanNumbers(
    await rpc<string[]>("alert_sms_recipients", { p_alert_id: d.alert.alert_id }),
    semaphoreNumber,
  );
  const budget = await rpc<{ left: number }>("alert_sms_budget");
  const plan = planBroadcast(numbers, budget.left);
  const message = alertSmsText(d.alert.title, d.alert.body);
  const sender = Deno.env.get("SEMAPHORE_SENDER_NAME");

  let accepted = 0;
  for (const batch of chunk(plan.send)) {
    const form = new URLSearchParams({ apikey: apiKey, number: batch.join(","), message });
    if (sender) form.set("sendername", sender);
    let ok = 0;
    let detail: string | null = null;
    try {
      const res = await fetch("https://api.semaphore.co/api/v4/messages", {
        method: "POST",
        body: form,
      });
      ok = acceptedCount(res.ok, await res.json().catch(() => null), batch.length);
      if (ok < batch.length) detail = `HTTP ${res.status}`;
    } catch {
      detail = "Semaphore could not be reached";
    }
    accepted += ok;
    // The log of texts (full numbers; no client can read it).
    await rest(
      "sms_log",
      batch.map((to, i) => ({
        kind: "alert",
        to_number: to,
        body: message,
        provider: "semaphore",
        status: i < ok ? "sent" : "failed",
        detail: i < ok ? d.alert.alert_id : `${d.alert.alert_id}: ${detail}`,
      })),
    ).catch(() => {});
    if (batch.length > 0) {
      console.log(
        `send-alerts: ${ok} of ${batch.length} accepted, first ${maskNumber(batch[0])}`,
      );
    }
  }
  return smsOutcome(numbers.length, accepted, plan.overCap);
}

/** One rescue text to one resident. The number is never logged in full. */
async function sendConfirmation(
  c: ClaimedConfirmation,
  apiKey: string | undefined,
): Promise<ConfirmationOutcome> {
  if (!apiKey) return { status: "notSetUp", detail: "No Semaphore key" };
  const to = semaphoreNumber(c.to ?? "");
  if (!to) return { status: "failed", detail: "No mobile number on record" };
  const message = confirmationSmsText(c);
  const form = new URLSearchParams({ apikey: apiKey, number: to, message });
  const sender = Deno.env.get("SEMAPHORE_SENDER_NAME");
  if (sender) form.set("sendername", sender);

  let ok = false;
  let detail: string | null = null;
  try {
    const res = await fetch("https://api.semaphore.co/api/v4/messages", {
      method: "POST",
      body: form,
    });
    ok = acceptedCount(res.ok, await res.json().catch(() => null), 1) === 1;
    if (!ok) detail = `HTTP ${res.status}`;
  } catch {
    detail = "Semaphore could not be reached";
  }
  await rest("sms_log", {
    kind: "rescue",
    to_number: to,
    body: message,
    provider: "semaphore",
    status: ok ? "sent" : "failed",
    detail: ok ? c.incident_id : `${c.incident_id}: ${detail}`,
  }).catch(() => {});
  console.log(
    `send-alerts: ${c.incident_id} ${c.kind} ${ok ? "sent" : "failed"} to ${maskNumber(to)}`,
  );
  return { status: ok ? "sent" : "failed", detail };
}

/** Works through the rescue texts waiting to go. Returns each outcome. */
async function sendConfirmations(apiKey: string | undefined): Promise<Record<string, string>> {
  let claimed: ClaimedConfirmation[];
  try {
    claimed = await rpc<ClaimedConfirmation[]>("claim_rescue_confirmations");
  } catch (e) {
    // Alerts still go out.
    console.log(`send-alerts: could not claim rescue confirmations (${(e as Error).message})`);
    return {};
  }
  const results: Record<string, string> = {};
  for (const c of claimed) {
    let outcome: ConfirmationOutcome;
    try {
      outcome = await sendConfirmation(c, apiKey);
    } catch (e) {
      outcome = { status: "failed", detail: (e as Error).message.slice(0, 200) };
    }
    await rpc("finish_rescue_confirmation", {
      p_confirmation_id: c.confirmation_id,
      p_status: outcome.status,
      p_detail: outcome.detail,
    }).catch(() => {});
    results[`${c.incident_id}:${c.kind}`] = outcome.status;
  }
  return results;
}

// ------------------------------------------------------------ push (FCM)

/** Firebase, signed in once per run; null when it is not set up. */
interface Fcm {
  account: ServiceAccount;
  token: string;
}

async function firebase(): Promise<Fcm | null | Error> {
  const account = parseServiceAccount(Deno.env.get("FIREBASE_SERVICE_ACCOUNT"));
  if (!account) return null;
  try {
    return { account, token: await accessToken(account, fetch) };
  } catch (e) {
    return e as Error;
  }
}

interface ClaimedPush {
  message_id: number;
  kind: "rescue" | "assignment";
  title: string;
  body: string;
  data: Record<string, unknown>;
  tokens: string[];
}

/** Rescue confirmations and new assignments to the account's phones. */
async function sendPushMessages(
  getFcm: () => Promise<Fcm | null | Error>,
): Promise<Record<string, string>> {
  let claimed: ClaimedPush[];
  try {
    claimed = await rpc<ClaimedPush[]>("claim_push_messages");
  } catch (e) {
    console.log(`send-alerts: could not claim pushes (${(e as Error).message})`);
    return {};
  }
  const results: Record<string, string> = {};
  // Signs in to Firebase only when there is something to send.
  const fcm = claimed.length > 0 ? await getFcm() : null;
  const stale: string[] = [];
  for (const m of claimed) {
    let status: "sent" | "failed" | "notSetUp";
    let delivered: number | null = null;
    let detail: string | null = null;
    if (fcm === null) {
      status = "notSetUp";
      detail = "Push needs the Firebase project";
    } else if (fcm instanceof Error) {
      status = "failed";
      detail = fcm.message;
    } else {
      const message = (to: string) =>
        fcmMessage({ token: to }, m.title, m.body, m.data, channels[m.kind]);
      delivered = 0;
      const errors = new Set<string>();
      for (const to of m.tokens) {
        const r = await sendMessage(fcm.account.project_id, fcm.token, message(to), fetch);
        if (r.ok) delivered++;
        if (r.stale) stale.push(to);
        if (r.detail) errors.add(r.detail);
      }
      status = delivered > 0 ? "sent" : "failed";
      detail = errors.size > 0 ? [...errors].join(", ") : null;
    }
    await rpc("finish_push_message", {
      p_message_id: m.message_id,
      p_status: status,
      p_devices: m.tokens.length,
      p_delivered: delivered,
      p_detail: detail,
    }).catch(() => {});
    results[`push:${m.message_id}:${m.kind}`] = status;
  }
  if (stale.length > 0) {
    await rpc("forget_push_tokens", { p_tokens: stale }).catch(() => {});
    console.log(`send-alerts: ${stale.length} phone token(s) no longer exist`);
  }
  return results;
}

/** An alert to the topics of its area (FR6, FR14). */
async function sendAlertPush(d: ClaimedDelivery, fcm: Fcm | Error): Promise<Outcome> {
  if (fcm instanceof Error) {
    return { status: "failed", recipients: null, delivered: null, failed: null, detail: fcm.message };
  }
  const targets: Target[] = alertTargets(d.alert.barangays);
  let ok = 0;
  const errors = new Set<string>();
  for (const target of targets) {
    const r = await sendMessage(
      fcm.account.project_id,
      fcm.token,
      fcmMessage(target, d.alert.title, d.alert.body, { type: "alert", alert_id: d.alert.alert_id }, channels.alert),
      fetch,
    );
    if (r.ok) ok++;
    else if (r.detail) errors.add(r.detail);
  }
  // Topics do not say how many phones they reached.
  return {
    status: ok > 0 ? "sent" : "failed",
    recipients: null,
    delivered: null,
    failed: null,
    detail: ok === targets.length
      ? null
      : `${targets.length - ok} of ${targets.length} topic sends failed: ${[...errors].join(", ")}`,
  };
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("ALERTS_SECRET");
  if (!secret || !url || !serviceKey) return json(500, { error: "send-alerts is not set up" });
  if (!authorized(req.headers, secret)) return json(401, { error: "unauthorized" });

  const apiKey = Deno.env.get("SEMAPHORE_API_KEY");
  // A resident waiting for rescue comes before a broadcast.
  const results = await sendConfirmations(apiKey);
  let signedIn: Promise<Fcm | null | Error> | undefined;
  const getFcm = () => {
    signedIn ??= firebase().then((f) => {
      if (f instanceof Error) console.log(`send-alerts: ${f.message}`);
      return f;
    });
    return signedIn;
  };
  Object.assign(results, await sendPushMessages(getFcm));
  const personal = Object.keys(results).length;

  let claimed: ClaimedDelivery[];
  try {
    claimed = await rpc<ClaimedDelivery[]>("claim_alert_deliveries");
  } catch (e) {
    console.log(`send-alerts: could not claim deliveries (${(e as Error).message})`);
    return json(502, { error: "could not read the queue" });
  }

  for (const d of claimed) {
    let outcome: Outcome;
    try {
      if (d.alert.ended) {
        outcome = ended;
      } else if (d.channel === "sms" && apiKey) {
        outcome = await sendSms(d, apiKey);
      } else if (d.channel === "push" && (await getFcm()) !== null) {
        outcome = await sendAlertPush(d, (await getFcm())!);
      } else {
        outcome = notSetUp(d.channel);
      }
    } catch (e) {
      outcome = {
        status: "failed",
        recipients: null,
        delivered: null,
        failed: null,
        detail: (e as Error).message.slice(0, 200),
      };
    }
    await finish(d, outcome).catch(() => {});
    results[`${d.alert.alert_id}:${d.channel}`] = outcome.status;
    console.log(`send-alerts: ${d.alert.alert_id} ${d.channel} ${outcome.status}`);
  }
  return json(200, { processed: personal + claimed.length, results });
});
