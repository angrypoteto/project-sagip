// Run with: node --test supabase/functions/send-alerts/fcm.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";

import {
  accessToken,
  alertTargets,
  allManilaTopic,
  fcmMessage,
  isStaleToken,
  parseServiceAccount,
  sendMessage,
  signedAssertion,
  topicForBarangay,
} from "./fcm.ts";

/** A throwaway RSA key in the shape of a Firebase service account file. */
async function testAccount() {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let raw = "";
  for (const b of der) raw += String.fromCharCode(b);
  const pem = `-----BEGIN PRIVATE KEY-----\n${btoa(raw).match(/.{1,64}/g)!.join("\n")}\n-----END PRIVATE KEY-----\n`;
  const json = JSON.stringify({
    type: "service_account",
    project_id: "sagip-test",
    client_email: "sender@sagip-test.iam.gserviceaccount.com",
    private_key: pem,
    token_uri: "https://oauth2.googleapis.com/token",
  });
  return { json, publicKey: pair.publicKey };
}

function decode(part: string): unknown {
  const b64 = part.replace(/-/g, "+").replace(/_/g, "/");
  return JSON.parse(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)));
}

test("the service account secret is read, or refused when it is not one", async () => {
  const { json } = await testAccount();
  const sa = parseServiceAccount(json)!;
  assert.equal(sa.project_id, "sagip-test");
  assert.equal(sa.token_uri, "https://oauth2.googleapis.com/token");
  assert.equal(parseServiceAccount(undefined), null);
  assert.equal(parseServiceAccount("not json"), null);
  assert.equal(parseServiceAccount(JSON.stringify({ project_id: "x" })), null);
});

test("the token request is a JWT signed with the account's key", async () => {
  const { json, publicKey } = await testAccount();
  const sa = parseServiceAccount(json)!;
  const jwt = await signedAssertion(sa, 1_790_000_000);
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(decode(header), { alg: "RS256", typ: "JWT" });
  assert.deepEqual(decode(claims), {
    iss: "sender@sagip-test.iam.gserviceaccount.com",
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: 1_790_000_000,
    exp: 1_790_003_600,
  });
  const sig = Uint8Array.from(
    atob(signature.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - (signature.length % 4)) % 4)),
    (c) => c.charCodeAt(0),
  );
  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    sig,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  assert.ok(valid, "Google can check the signature with the account's public key");
});

test("the access token comes from Google's token endpoint", async () => {
  const { json } = await testAccount();
  const sa = parseServiceAccount(json)!;
  let form: URLSearchParams | null = null;
  const ok = (async (_url: string | URL | Request, init?: RequestInit) => {
    form = init!.body as URLSearchParams;
    return new Response(JSON.stringify({ access_token: "ya29.test", expires_in: 3599 }));
  }) as typeof fetch;
  assert.equal(await accessToken(sa, ok, 1_790_000_000), "ya29.test");
  assert.equal(form!.get("grant_type"), "urn:ietf:params:oauth:grant-type:jwt-bearer");
  assert.equal(form!.get("assertion")!.split(".").length, 3);

  const refused = (async () => new Response(JSON.stringify({ error: "invalid_grant" }), { status: 400 })) as typeof fetch;
  await assert.rejects(accessToken(sa, refused), /Firebase sign-in refused \(HTTP 400\)/);
});

test("barangay topics: the same vectors as the Dart side", () => {
  // packages/shared test/push_test.dart checks the same pairs.
  const vectors: [string, string][] = [
    ["Barangay 412", "area-barangay-412"],
    ["Barangay 105", "area-barangay-105"],
    ["  Barangay  649 ", "area-barangay-649"],
    ["Barangay 830 (Pandacan)", "area-barangay-830-pandacan"],
    ["Sta. Ana", "area-sta-ana"],
    ["España", "area-espana"],
    ["Peñafrancia", "area-penafrancia"],
    ["***", "area-unknown"],
  ];
  for (const [name, topic] of vectors) assert.equal(topicForBarangay(name), topic, name);
  for (const [, topic] of vectors) assert.match(topic, /^[a-zA-Z0-9-_.~%]{1,900}$/);
});

test("an alert goes to all of Manila, or to its barangays five at a time", () => {
  assert.deepEqual(alertTargets([]), [{ topic: allManilaTopic }]);
  assert.deepEqual(alertTargets(["Barangay 412"]), [{ topic: "area-barangay-412" }]);
  assert.deepEqual(alertTargets(["Barangay 412", "Barangay 490", "Barangay 412"]), [
    { condition: "'area-barangay-412' in topics || 'area-barangay-490' in topics" },
  ]);
  const seven = alertTargets(Array.from({ length: 7 }, (_, i) => `Barangay ${100 + i}`));
  assert.equal(seven.length, 2);
  assert.equal((seven[0] as { condition: string }).condition.split("||").length, 5);
  assert.deepEqual(seven[1], {
    condition: "'area-barangay-105' in topics || 'area-barangay-106' in topics",
  });
});

test("a message carries the text, string data, and the Android channel", () => {
  const m = fcmMessage(
    { token: "t1" },
    "A rescue team is coming",
    "R-03 has been sent to your location.",
    { type: "rescue", incident_id: "INC-0152", confirmation_id: 12, missing: null },
    "sagip_rescue",
  );
  assert.deepEqual(m, {
    message: {
      token: "t1",
      notification: { title: "A rescue team is coming", body: "R-03 has been sent to your location." },
      data: { type: "rescue", incident_id: "INC-0152", confirmation_id: "12" },
      android: { priority: "high", notification: { channel_id: "sagip_rescue" } },
    },
  });
  const long = fcmMessage({ topic: "manila" }, "T", "x".repeat(800), {}, "sagip_alerts") as {
    message: { notification: { body: string } };
  };
  assert.equal(long.message.notification.body.length, 500);
});

test("tokens FCM no longer knows are recognised; other errors are not", () => {
  const fcmError = (code: string) => ({
    error: { details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: code }] },
  });
  assert.ok(isStaleToken(404, fcmError("UNREGISTERED")));
  assert.ok(isStaleToken(403, fcmError("SENDER_ID_MISMATCH")));
  assert.ok(!isStaleToken(400, fcmError("INVALID_ARGUMENT")), "may be our own message's fault");
  assert.ok(!isStaleToken(429, fcmError("QUOTA_EXCEEDED")));
  assert.ok(!isStaleToken(500, null));
});

test("sending never throws", async () => {
  const down = (async () => {
    throw new Error("offline");
  }) as typeof fetch;
  assert.deepEqual(await sendMessage("p", "tok", {}, down), {
    ok: false,
    stale: false,
    detail: "FCM could not be reached",
  });
  let target = "";
  const up = (async (url: string | URL | Request, init?: RequestInit) => {
    target = String(url);
    assert.equal((init!.headers as Record<string, string>).Authorization, "Bearer tok");
    return new Response(JSON.stringify({ name: "projects/p/messages/1" }));
  }) as typeof fetch;
  assert.deepEqual(await sendMessage("p", "tok", {}, up), { ok: true, stale: false, detail: null });
  assert.equal(target, "https://fcm.googleapis.com/v1/projects/p/messages:send");
});
