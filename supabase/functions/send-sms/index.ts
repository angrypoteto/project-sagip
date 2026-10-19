// Supabase Auth "Send SMS" hook (plan Q37): texts the resident's sign-in
// code (S3 to S5).
//
// - With the gateway phone set up (SMS_GATEWAY_SEND_URL,
//   SMS_GATEWAY_USERNAME, SMS_GATEWAY_PASSWORD: SMS Gateway for Android,
//   cloud mode), the code is texted from the gateway SIM: free apart from
//   the SIM's load. sms_log records that it was sent (without the code).
// - Else with SEMAPHORE_API_KEY set, through Semaphore's OTP route.
// - Without it (development, before the Semaphore account exists), nothing
//   is sent: the message, code included, is kept in sms_log for an hour so
//   the demo can read it in the Table Editor.
//
// Secrets (Edge Functions > Secrets): SEND_SMS_HOOK_SECRET (from the hook
// settings, "v1,whsec_..."), and either the three SMS_GATEWAY_ secrets or
// SEMAPHORE_API_KEY (with SEMAPHORE_SENDER_NAME once Semaphore approves
// it). SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the
// platform.
//
// Deploy with JWT checking off (Auth signs the call instead):
//   supabase functions deploy send-sms --no-verify-jwt

import { verifyWebhook } from "../_shared/standard_webhooks.ts";
import { gatewayLogin, gatewaySendRequest } from "../sms-intake/intake.ts";
import {
  hookError,
  maskNumber,
  otpMessage,
  otpSeconds,
  parsePayload,
  semaphoreNumber,
} from "./sms.ts";

async function logSms(row: Record<string, unknown>): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return;
  await fetch(`${url}/rest/v1/sms_log`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(row),
  });
}

Deno.serve(async (req) => {
  const secret = Deno.env.get("SEND_SMS_HOOK_SECRET");
  if (!secret) return hookError(500, "The SMS hook is not set up.");
  const body = await req.text();
  if (!(await verifyWebhook(secret, body, req.headers))) {
    return hookError(401, "Bad signature.");
  }
  const payload = parsePayload(body);
  const number = payload ? semaphoreNumber(payload.user.phone) : null;
  if (!payload || !number) return hookError(400, "Not a Philippine mobile number.");

  const message = otpMessage(payload.sms.otp);
  const apiKey = Deno.env.get("SEMAPHORE_API_KEY");
  const gateway = gatewayLogin((name) => Deno.env.get(name));

  if (gateway) {
    // From the gateway SIM. The code is in the text, so the log hides it.
    // A code that could not go out before it expires is not sent late.
    const request = gatewaySendRequest(
      gateway.url,
      gateway.username,
      gateway.password,
      number,
      message,
      otpSeconds,
    )!;
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
      kind: "otp",
      to_number: number,
      body: "Sign-in code (hidden)",
      provider: "gateway",
      status: ok ? "sent" : "failed",
      detail,
    });
    console.log(`send-sms: ${ok ? "sent" : "failed"} for ${maskNumber(number)} (gateway)`);
    if (!ok) return hookError(502, "The SMS gateway did not accept the message.");
    return new Response("{}", { headers: { "Content-Type": "application/json" } });
  }

  if (!apiKey) {
    // Development: keep the message so the demo can read the code.
    await logSms({
      kind: "otp",
      to_number: number,
      body: message,
      provider: "dev",
      status: "notSent",
    });
    console.log(`send-sms: code kept for ${maskNumber(number)} (no SMS provider)`);
    return new Response("{}", { headers: { "Content-Type": "application/json" } });
  }

  const form = new URLSearchParams({
    apikey: apiKey,
    number,
    message: otpMessage("{otp}"),
    code: payload.sms.otp,
  });
  const sender = Deno.env.get("SEMAPHORE_SENDER_NAME");
  if (sender) form.set("sendername", sender);

  const res = await fetch("https://api.semaphore.co/api/v4/otp", {
    method: "POST",
    body: form,
  });
  const ok = res.ok;
  await logSms({
    kind: "otp",
    to_number: number,
    body: "Sign-in code (hidden)",
    provider: "semaphore",
    status: ok ? "sent" : "failed",
    detail: ok ? null : `HTTP ${res.status}`,
  });
  console.log(`send-sms: ${ok ? "sent" : "failed"} for ${maskNumber(number)}`);
  if (!ok) return hookError(502, "The SMS provider did not accept the message.");
  return new Response("{}", { headers: { "Content-Type": "application/json" } });
});
