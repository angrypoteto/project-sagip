// sms-intake: Tier 2 SOS by SMS (plan section 11, NFR1, FR8).
//
// The MDRRMD gateway SIM (a GSM modem service or an Android phone running
// an SMS gateway app) forwards each inbound text here. A SAGIP1 message
// becomes an SOS on the board through intake_sms_sos(); the same SOS sent
// later by the app over the internet is recognised by its id. Every inbound
// text is kept in sms_log (no client access).
//
// The reply to the resident (plan: acknowledgement from the gateway SIM):
// - with SMS_GATEWAY_SEND_URL, SMS_GATEWAY_USERNAME, and
//   SMS_GATEWAY_PASSWORD set, this function asks the gateway phone's app
//   (SMS Gateway for Android, cloud mode) to send it from the SIM;
// - else with SEMAPHORE_API_KEY and SMS_ACK_VIA_SEMAPHORE=true, through
//   Semaphore;
// - else it comes back in the response as `reply` for the gateway to send.
// Either way it is logged in sms_log (kind `ack`).
//
// Secrets (Edge Functions > Secrets): SMS_INTAKE_SECRET (shared with the
// gateway), optional SMS_GATEWAY_SEND_URL, SMS_GATEWAY_USERNAME,
// SMS_GATEWAY_PASSWORD, SEMAPHORE_API_KEY, SEMAPHORE_SENDER_NAME,
// SMS_ACK_VIA_SEMAPHORE. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are
// provided by the platform.
//
// Deploy with JWT checking off (the gateway uses the shared secret):
//   supabase functions deploy sms-intake --no-verify-jwt

import { decodeSosSms, SosSmsError } from "../_shared/sos_sms.ts";
import { maskNumber, semaphoreNumber } from "../send-sms/sms.ts";
import {
  ackMessage,
  authorized,
  gatewaySendRequest,
  parseGatewayPayload,
  unreadableMessage,
} from "./intake.ts";

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

async function logSms(row: Record<string, unknown>): Promise<void> {
  if (!url || !serviceKey) return;
  await rest("sms_log", row).catch(() => {});
}

async function sendAckViaSemaphore(to: string, message: string): Promise<boolean> {
  const apiKey = Deno.env.get("SEMAPHORE_API_KEY");
  const number = semaphoreNumber(to);
  if (!apiKey || !number) return false;
  const form = new URLSearchParams({ apikey: apiKey, number, message });
  const sender = Deno.env.get("SEMAPHORE_SENDER_NAME");
  if (sender) form.set("sendername", sender);
  const res = await fetch("https://api.semaphore.co/api/v4/messages", {
    method: "POST",
    body: form,
  });
  await logSms({
    kind: "ack",
    to_number: to,
    body: message,
    provider: "semaphore",
    status: res.ok ? "sent" : "failed",
    detail: res.ok ? null : `HTTP ${res.status}`,
  });
  return res.ok;
}

/** The reply from the gateway SIM, through the gateway app's API. */
async function sendAckViaGateway(to: string, message: string): Promise<boolean> {
  const endpoint = Deno.env.get("SMS_GATEWAY_SEND_URL");
  const username = Deno.env.get("SMS_GATEWAY_USERNAME");
  const password = Deno.env.get("SMS_GATEWAY_PASSWORD");
  if (!endpoint || !username || !password) return false;
  const request = gatewaySendRequest(endpoint, username, password, to, message);
  if (!request) return false;
  let ok = false;
  let detail: string | null = null;
  try {
    const res = await fetch(request.url, request.init);
    ok = res.ok;
    if (!ok) detail = `HTTP ${res.status}`;
  } catch {
    detail = "the gateway app could not be reached";
  }
  await logSms({
    kind: "ack",
    to_number: to,
    body: message,
    provider: "gateway",
    status: ok ? "sent" : "failed",
    detail,
  });
  return ok;
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SMS_INTAKE_SECRET");
  if (!secret || !url || !serviceKey) return json(500, { error: "sms-intake is not set up" });
  if (!authorized(req.headers, secret)) return json(401, { error: "unauthorized" });

  const inbound = parseGatewayPayload(await req.json().catch(() => null));
  if (!inbound) return json(400, { error: "unrecognised payload" });
  const who = maskNumber(inbound.from);

  let sos;
  try {
    sos = decodeSosSms(inbound.text);
  } catch (e) {
    const reason = e instanceof SosSmsError ? e.reason : "not_sagip";
    await logSms({
      kind: "inbound",
      to_number: inbound.from,
      body: inbound.text.slice(0, 1000),
      provider: "gateway",
      status: "unreadable",
      detail: reason,
    });
    console.log(`sms-intake: unreadable text from ${who} (${reason})`);
    return json(200, { status: "unreadable", reason, reply: unreadableMessage() });
  }

  const res = await rest("rpc/intake_sms_sos", {
    p_from: inbound.from,
    p_client_uuid: sos.clientId,
    p_captured_at: sos.capturedAt.toISOString(),
    p_latitude: sos.lat,
    p_longitude: sos.lng,
    p_accuracy_m: sos.accuracyM,
    p_mock_location: sos.mockLocation,
  });
  if (!res.ok) {
    // Let the gateway retry: an SOS must not be lost.
    console.log(`sms-intake: database refused an SOS from ${who} (HTTP ${res.status})`);
    return json(502, { error: "could not file the SOS" });
  }
  const result = await res.json() as {
    incident_id: string;
    duplicate: boolean;
    known: boolean;
  };
  await logSms({
    kind: "inbound",
    to_number: inbound.from,
    body: inbound.text,
    provider: "gateway",
    status: "received",
    detail: `${result.incident_id}${result.duplicate ? " (already on the board)" : ""}`,
  });
  console.log(
    `sms-intake: SOS ${result.incident_id} from ${who}${result.duplicate ? " (duplicate)" : ""}`,
  );

  const reply = ackMessage(result.incident_id, result.known);
  let replySent = false;
  if (!result.duplicate) {
    replySent = await sendAckViaGateway(inbound.from, reply);
    if (!replySent && Deno.env.get("SMS_ACK_VIA_SEMAPHORE") === "true") {
      replySent = await sendAckViaSemaphore(inbound.from, reply);
    }
  }
  return json(200, {
    status: result.duplicate ? "duplicate" : "created",
    incident_id: result.incident_id,
    // The gateway sends this from its SIM unless it was already sent.
    reply: replySent || result.duplicate ? null : reply,
  });
});
