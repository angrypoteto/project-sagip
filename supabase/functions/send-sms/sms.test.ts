// Run with: node --test supabase/functions/send-sms/sms.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";

import { sign, verifyWebhook } from "../_shared/standard_webhooks.ts";
import {
  maskNumber,
  otpMessage,
  parsePayload,
  semaphoreNumber,
} from "./sms.ts";

// Made-up secrets in Supabase's format ("v1,whsec_" + base64). Built here
// rather than written out, so secret scanners do not take them for real
// keys (GitHub read them as Stripe webhook secrets, 2026-10-20).
const testSecret = (text: string) => ["v1", `whsec_${btoa(text)}`].join(",");
const secret = testSecret("sagip-test-secret-0123456789");

function headers(map: Record<string, string>) {
  return { get: (name: string) => map[name] ?? null };
}

test("the code message fits one SMS", () => {
  const m = otpMessage("123456");
  assert.ok(m.includes("123456"));
  assert.ok(m.length <= 160);
});

test("numbers become Semaphore's local form, or null", () => {
  assert.equal(semaphoreNumber("639170004821"), "09170004821");
  assert.equal(semaphoreNumber("+63 917 000 4821"), "09170004821");
  assert.equal(semaphoreNumber("09170004821"), "09170004821");
  assert.equal(semaphoreNumber("0285270000"), null, "landline");
  assert.equal(semaphoreNumber("12025550123"), null, "not Philippine");
});

test("logs only see masked numbers", () => {
  assert.equal(maskNumber("639170004821"), "0917 ••• 4821");
  assert.equal(maskNumber("09170004821"), "0917 ••• 4821");
});

test("the payload is read defensively", () => {
  assert.deepEqual(
    parsePayload('{"user":{"id":"u1","phone":"639170004821"},"sms":{"otp":"123456"}}'),
    { user: { id: "u1", phone: "639170004821" }, sms: { otp: "123456" } },
  );
  assert.equal(parsePayload("not json"), null);
  assert.equal(parsePayload('{"user":{}}'), null);
});

test("a correctly signed, recent hook call is accepted", async () => {
  const body = '{"user":{"phone":"639170004821"},"sms":{"otp":"123456"}}';
  const now = 1_790_000_000;
  const sig = await sign(secret, "msg_1", String(now), body);
  assert.ok(
    await verifyWebhook(
      secret,
      body,
      headers({
        "webhook-id": "msg_1",
        "webhook-timestamp": String(now),
        "webhook-signature": `v1,${sig}`,
      }),
      now + 10,
    ),
  );
});

test("a changed body, wrong secret, or old timestamp is refused", async () => {
  const body = '{"sms":{"otp":"123456"}}';
  const now = 1_790_000_000;
  const sig = await sign(secret, "msg_1", String(now), body);
  const good = {
    "webhook-id": "msg_1",
    "webhook-timestamp": String(now),
    "webhook-signature": `v1,${sig}`,
  };
  assert.equal(
    await verifyWebhook(secret, '{"sms":{"otp":"999999"}}', headers(good), now),
    false,
  );
  assert.equal(
    await verifyWebhook(
      testSecret("other-secret-0123456789"),
      body,
      headers(good),
      now,
    ),
    false,
  );
  assert.equal(await verifyWebhook(secret, body, headers(good), now + 3600), false);
  assert.equal(await verifyWebhook(secret, body, headers({}), now), false);
});
