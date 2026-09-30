// Supabase Auth "Send SMS" hook (plan Q37): texts the resident's sign-in
// code (S3 to S5).
//
// - With SEMAPHORE_API_KEY set, the code goes out through Semaphore's OTP
//   route, and sms_log records that it was sent (without the code).
// - Without it (development, before the Semaphore account exists), nothing
//   is sent: the message, code included, is kept in sms_log for an hour so
//   the demo can read it in the Table Editor.
//
// Secrets (Edge Functions > Secrets): SEND_SMS_HOOK_SECRET (from the hook
// settings, "v1,whsec_..."), SEMAPHORE_API_KEY, SEMAPHORE_SENDER_NAME
// (optional; must be approved by Semaphore). SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are provided by the platform.
//
// Deploy with JWT checking off (Auth signs the call instead):
//   supabase functions deploy send-sms --no-verify-jwt

import { verifyWebhook } from "../_shared/standard_webhooks.ts";
import {
  hookError,
  maskNumber,
  otpMessage,
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
