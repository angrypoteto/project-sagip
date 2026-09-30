// Run with: node --test supabase/functions/sms-intake/sms_intake.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

import {
  crc16Hex,
  decodeSosSms,
  encodeSosSms,
  SosSmsError,
} from "../_shared/sos_sms.ts";
import {
  ackMessage,
  authorized,
  parseGatewayPayload,
  unreadableMessage,
} from "./intake.ts";

// The same vectors the Dart codec is tested against.
const vectors = JSON.parse(
  readFileSync(
    new URL("../../../packages/shared/test/fixtures/sos_sms_vectors.json", import.meta.url),
    "utf8",
  ),
);

test("CRC-16/CCITT-FALSE matches the standard check value", () => {
  assert.equal(crc16Hex(vectors.crc_check.text), vectors.crc_check.crc);
});

test("the Dart vectors decode and re-encode identically", () => {
  for (const m of vectors.messages) {
    const s = decodeSosSms(m.text);
    assert.equal(s.clientId, m.client_id);
    assert.equal(s.lat, m.lat);
    assert.equal(s.lng, m.lng);
    assert.equal(s.accuracyM, m.accuracy_m);
    assert.equal(s.capturedAt.toISOString().replace(".000", ""), m.captured_at);
    assert.equal(s.mockLocation, m.mock);
    assert.equal(encodeSosSms(s), m.text);
  }
});

test("changed or foreign texts are refused with a reason", () => {
  const good = vectors.messages[0].text as string;
  const reason = (text: string) => {
    try {
      decodeSosSms(text);
      return "ok";
    } catch (e) {
      return (e as SosSmsError).reason;
    }
  };
  assert.equal(reason("Tulong! Baha dito sa Tondo"), "not_sagip");
  assert.equal(reason(good.replace("14.60912", "14.60913")), "bad_checksum");
  const body = "SAGIP1 SOS 1234 14.6,121.0 8 1790754133 -";
  assert.equal(reason(`${body} ${crc16Hex(body)}`), "bad_field");
  const plus = "SAGIP1 SOS 3f2a9c1e7b4d4e0a9c2f1a2b3c4d5e6f 14.6,121.0 +8 1790754133 -";
  assert.equal(reason(`${plus} ${crc16Hex(plus)}`), "bad_field");
});

test("both gateway payload shapes are read", () => {
  assert.deepEqual(
    parseGatewayPayload({
      event: "sms:received",
      payload: { message: "SAGIP1 ...", phoneNumber: "+639170004821", receivedAt: "2026-10-01T00:00:00Z" },
    }),
    { from: "+639170004821", text: "SAGIP1 ...", receivedAt: "2026-10-01T00:00:00Z" },
  );
  assert.deepEqual(
    parseGatewayPayload({ from: "09170004821", text: "hello" }),
    { from: "09170004821", text: "hello", receivedAt: null },
  );
  assert.equal(parseGatewayPayload({ event: "sms:sent", payload: { message: "x", phoneNumber: "1" } }), null);
  assert.equal(parseGatewayPayload("nope"), null);
  assert.equal(parseGatewayPayload({ from: 5, text: "x" }), null);
});

test("replies fit one SMS", () => {
  assert.ok(ackMessage("INC-0151", true).length <= 160);
  assert.ok(ackMessage("INC-0151", false).length <= 160);
  assert.ok(unreadableMessage().length <= 160);
});

test("the gateway must send the shared secret", () => {
  const h = (map: Record<string, string>) => ({ get: (n: string) => map[n] ?? null });
  assert.ok(authorized(h({ "x-sagip-key": "s3cret-value" }), "s3cret-value"));
  assert.ok(authorized(h({ authorization: "Bearer s3cret-value" }), "s3cret-value"));
  assert.equal(authorized(h({ "x-sagip-key": "wrong-value!" }), "s3cret-value"), false);
  assert.equal(authorized(h({}), "s3cret-value"), false);
});
