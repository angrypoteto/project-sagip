// send-alerts: works through queued alert deliveries (FR6, plan section 12).
//
// Each alert (from the threshold engine or MDRRMD) has one delivery row per
// channel. This function claims the queued ones and:
// - SMS: texts the registered residents of the affected barangays, one SMS
//   each, up to the daily cap set on A3 (channels.sms_daily_cap): from the
//   gateway phone's SIM when SMS_GATEWAY_SEND_URL, SMS_GATEWAY_USERNAME, and
//   SMS_GATEWAY_PASSWORD are set (SMS Gateway for Android, cloud mode; the
//   free route), else through Semaphore. Every text is kept in sms_log; the delivery
//   row gets the counts.
// - Push: sent through Firebase Cloud Messaging to topics: "manila" for an
//   alert for all of Manila, else the topics of its barangays (the app
//   subscribes each resident to both). Marked "not set up" without the
//   FIREBASE_SERVICE_ACCOUNT secret.
// - Facebook: posted on the MDRRMD Facebook Page through the Graph API
//   with the Page's access token (FACEBOOK_PAGE_ID, FACEBOOK_PAGE_TOKEN);
//   marked "not set up" without them. The channel is off on A3 by default.
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
// The database calls it whenever something is queued (migration
// sender_wakeup: triggers on alert_delivery, rescue_confirmation, and
// push_message, through pg_net), with the shared secret as `x-sagip-key`.
// A run with nothing queued does nothing, so extra calls are harmless.
//
// The shared secret is ALERTS_SECRET when that secret is set, else the one
// the database keeps in its vault (read through sender_secret(), which only
// the service role may call), so no secret has to be copied by hand.
//
// POST {"check": true} with the secret reports what is set up (Firebase
// signed in or why not, Semaphore key present) and sends nothing.
//
// Secrets (Edge Functions > Secrets): the three SMS_GATEWAY_ secrets or
// SEMAPHORE_API_KEY (optional SEMAPHORE_SENDER_NAME), FIREBASE_SERVICE_ACCOUNT (the whole JSON key
// file), FACEBOOK_PAGE_ID and FACEBOOK_PAGE_TOKEN (a long-lived Page access
// token that may post), optional FACEBOOK_GRAPH_VERSION, optional
// ALERTS_SECRET. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY
// are provided by the platform.
//
// Deploy with JWT checking off (the webhook uses the shared secret):
//   supabase functions deploy send-alerts --no-verify-jwt

import { maskNumber, semaphoreNumber } from "../send-sms/sms.ts";
import { authorized, type GatewayLogin, gatewayLogin, gatewaySendRequest } from "../sms-intake/intake.ts";
import {
  acceptedCount,
  alertSmsText,
  chunk,
  type ClaimedCheck,
  type ClaimedConfirmation,
  type ClaimedDelivery,
  cleanNumbers,
  type ConfirmationOutcome,
  confirmationSmsText,
  ended,
  facebookOutcome,
  facebookPostText,
  notSetUp,
  type Outcome,
  planBroadcast,
  smsCheckText,
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

/**
 * The shared secret: ALERTS_SECRET, or the database's vault copy (read once
 * per instance; tried again after a failure).
 */
let vaultSecret: Promise<string | null> | undefined;
async function sharedSecret(): Promise<string | null> {
  const fromEnv = Deno.env.get("ALERTS_SECRET");
  if (fromEnv) return fromEnv;
  vaultSecret ??= rpc<string | null>("sender_secret").catch(() => {
    vaultSecret = undefined;
    return null;
  });
  return await vaultSecret;
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

/** Where texts go: the gateway phone's SIM (free) or Semaphore (paid). */
type SmsRoute = { kind: "gateway"; login: GatewayLogin } | { kind: "semaphore"; apiKey: string };

function smsRoute(): SmsRoute | null {
  const login = gatewayLogin((name) => Deno.env.get(name));
  if (login) return { kind: "gateway", login };
  const apiKey = Deno.env.get("SEMAPHORE_API_KEY");
  return apiKey ? { kind: "semaphore", apiKey } : null;
}

/** The gateway takes this many numbers per request; the phone sends each. */
const gatewayBatch = 50;

/** One request to the gateway app: how many of [batch] it took. */
async function gatewaySend(
  login: GatewayLogin,
  batch: string[],
  message: string,
): Promise<{ ok: number; detail: string | null }> {
  const request = gatewaySendRequest(login.url, login.username, login.password, batch, message);
  if (!request) return { ok: 0, detail: "no mobile numbers" };
  try {
    const res = await fetch(request.url, request.init);
    return res.ok ? { ok: batch.length, detail: null } : { ok: 0, detail: `HTTP ${res.status}` };
  } catch {
    return { ok: 0, detail: "the gateway app could not be reached" };
  }
}

async function sendSms(d: ClaimedDelivery, route: SmsRoute): Promise<Outcome> {
  if (route.kind === "gateway") return await sendSmsViaGateway(d, route.login);
  return await sendSmsViaSemaphore(d, route.apiKey);
}

/** The alert from the gateway SIM, in batches, logged per number. */
async function sendSmsViaGateway(d: ClaimedDelivery, login: GatewayLogin): Promise<Outcome> {
  const numbers = cleanNumbers(
    await rpc<string[]>("alert_sms_recipients", { p_alert_id: d.alert.alert_id }),
    semaphoreNumber,
  );
  const budget = await rpc<{ left: number }>("alert_sms_budget");
  const plan = planBroadcast(numbers, budget.left);
  const message = alertSmsText(d.alert.title, d.alert.body);
  let accepted = 0;
  for (const batch of chunk(plan.send, gatewayBatch)) {
    const { ok, detail } = await gatewaySend(login, batch, message);
    accepted += ok;
    await rest(
      "sms_log",
      batch.map((to) => ({
        kind: "alert",
        to_number: to,
        body: message,
        provider: "gateway",
        status: ok > 0 ? "sent" : "failed",
        detail: ok > 0 ? d.alert.alert_id : `${d.alert.alert_id}: ${detail}`,
      })),
    ).catch(() => {});
    if (batch.length > 0) {
      console.log(`send-alerts: gateway took ${ok} of ${batch.length}, first ${maskNumber(batch[0])}`);
    }
  }
  return smsOutcome(numbers.length, accepted, plan.overCap);
}

async function sendSmsViaSemaphore(d: ClaimedDelivery, apiKey: string): Promise<Outcome> {
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
  route: SmsRoute | null,
): Promise<ConfirmationOutcome> {
  if (!route) return { status: "notSetUp", detail: "No SMS provider (the gateway phone or Semaphore)" };
  const to = semaphoreNumber(c.to ?? "");
  if (!to) return { status: "failed", detail: "No mobile number on record" };
  const message = confirmationSmsText(c);
  if (route.kind === "gateway") {
    const { ok, detail } = await gatewaySend(route.login, [to], message);
    await rest("sms_log", {
      kind: "rescue",
      to_number: to,
      body: message,
      provider: "gateway",
      status: ok ? "sent" : "failed",
      detail: ok ? c.incident_id : `${c.incident_id}: ${detail}`,
    }).catch(() => {});
    console.log(`send-alerts: ${c.incident_id} ${c.kind} ${ok ? "sent" : "failed"} to ${maskNumber(to)} (gateway)`);
    return { status: ok ? "sent" : "failed", detail };
  }
  const apiKey = route.apiKey;
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
async function sendConfirmations(route: SmsRoute | null): Promise<Record<string, string>> {
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
      outcome = await sendConfirmation(c, route);
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

/** The dispatchers' SMS checks (FR8), one text each. */
async function sendChecks(route: SmsRoute | null): Promise<Record<string, string>> {
  let claimed: ClaimedCheck[];
  try {
    claimed = await rpc<ClaimedCheck[]>("claim_sms_checks");
  } catch (e) {
    console.log(`send-alerts: could not claim SMS checks (${(e as Error).message})`);
    return {};
  }
  const results: Record<string, string> = {};
  for (const c of claimed) {
    const message = smsCheckText(c.incident_id);
    const to = semaphoreNumber(c.to ?? "");
    let status: "sent" | "failed" | "notSetUp";
    let detail: string | null = null;
    if (!route) {
      status = "notSetUp";
      detail = "No SMS provider (the gateway phone or Semaphore)";
    } else if (!to) {
      status = "failed";
      detail = "Not a mobile number";
    } else {
      if (route.kind === "gateway") {
        const r = await gatewaySend(route.login, [to], message);
        status = r.ok > 0 ? "sent" : "failed";
        detail = r.detail;
      } else {
        try {
          const res = await fetch("https://api.semaphore.co/api/v4/messages", {
            method: "POST",
            body: new URLSearchParams({ apikey: route.apiKey, number: to, message }),
          });
          const ok = acceptedCount(res.ok, await res.json().catch(() => null), 1) === 1;
          status = ok ? "sent" : "failed";
          detail = ok ? null : `HTTP ${res.status}`;
        } catch {
          status = "failed";
          detail = "Semaphore could not be reached";
        }
      }
      await rest("sms_log", {
        kind: "check",
        to_number: to,
        body: message,
        provider: route.kind,
        status: status === "sent" ? "sent" : "failed",
        detail: status === "sent" ? c.incident_id : `${c.incident_id}: ${detail}`,
      }).catch(() => {});
      console.log(`send-alerts: SMS check for ${c.incident_id} ${status} to ${maskNumber(to)}`);
    }
    await rpc("finish_sms_check", {
      p_check_id: c.check_id,
      p_status: status,
      p_detail: detail,
    }).catch(() => {});
    results[`check:${c.incident_id}`] = status;
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
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;
  const account = parseServiceAccount(raw);
  if (!account) {
    return new Error("FIREBASE_SERVICE_ACCOUNT is set but is not a Firebase service account key file");
  }
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

// ------------------------------------------------------------ Facebook

/** The Page and its token, or null when Facebook posting is not set up. */
function facebookPage(): { id: string; token: string } | null {
  const id = Deno.env.get("FACEBOOK_PAGE_ID");
  const token = Deno.env.get("FACEBOOK_PAGE_TOKEN");
  return id && token ? { id, token } : null;
}

/** One post on the Page. The token goes in the body and is never logged. */
async function postToFacebook(
  d: ClaimedDelivery,
  page: { id: string; token: string },
): Promise<Outcome> {
  const version = Deno.env.get("FACEBOOK_GRAPH_VERSION") ?? "v24.0";
  const form = new URLSearchParams({
    message: facebookPostText(d.alert),
    access_token: page.token,
  });
  try {
    const res = await fetch(
      `https://graph.facebook.com/${version}/${encodeURIComponent(page.id)}/feed`,
      { method: "POST", body: form },
    );
    return facebookOutcome(res.ok, await res.json().catch(() => null), res.status);
  } catch {
    return {
      status: "failed",
      recipients: null,
      delivered: null,
      failed: null,
      detail: "Facebook could not be reached",
    };
  }
}

Deno.serve(async (req) => {
  if (!url || !serviceKey) return json(500, { error: "send-alerts is not set up" });
  const secret = await sharedSecret();
  if (!secret) return json(500, { error: "send-alerts is not set up" });
  if (!authorized(req.headers, secret)) return json(401, { error: "unauthorized" });

  const request = await req.json().catch(() => null) as { check?: unknown } | null;
  if (request?.check === true) {
    // What is set up; nothing is claimed or sent. Names only, never values.
    const f = await firebase();
    return json(200, {
      firebase: f === null
        ? "FIREBASE_SERVICE_ACCOUNT is not set"
        : f instanceof Error
        ? f.message
        : `ready: signed in to project ${f.account.project_id}`,
      semaphore: Deno.env.get("SEMAPHORE_API_KEY") ? "key set" : "SEMAPHORE_API_KEY is not set",
      gateway: gatewayLogin((name) => Deno.env.get(name))
        ? "set: texts go from the gateway phone"
        : "SMS_GATEWAY_SEND_URL, SMS_GATEWAY_USERNAME, or SMS_GATEWAY_PASSWORD is not set",
      facebook: facebookPage()
        ? "page and token set"
        : "FACEBOOK_PAGE_ID or FACEBOOK_PAGE_TOKEN is not set",
      secret: Deno.env.get("ALERTS_SECRET") ? "ALERTS_SECRET" : "the database vault",
    });
  }

  const route = smsRoute();
  // A resident waiting for rescue comes before a broadcast.
  const results = await sendConfirmations(route);
  Object.assign(results, await sendChecks(route));
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
      } else if (d.channel === "sms" && route) {
        outcome = await sendSms(d, route);
      } else if (d.channel === "push" && (await getFcm()) !== null) {
        outcome = await sendAlertPush(d, (await getFcm())!);
      } else if (d.channel === "facebook" && facebookPage()) {
        outcome = await postToFacebook(d, facebookPage()!);
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
