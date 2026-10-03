// Run with: node --test supabase/functions/send-alerts/index.test.ts
//
// Runs the real handler in index.ts under Node, with Deno and the network
// replaced by stand-ins: the database calls and Semaphore are recorded and
// answered here. Nothing is sent anywhere.
import { test } from "node:test";
import assert from "node:assert/strict";

type Handler = (req: Request) => Promise<Response>;

const env: Record<string, string | undefined> = {
  SUPABASE_URL: "https://project.example",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
  ALERTS_SECRET: "shared-secret-for-tests",
  SEMAPHORE_API_KEY: "test-semaphore-key",
};

// A throwaway key in the shape of a Firebase service account file.
const firebaseKey = await (async () => {
  const pair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign"],
  );
  const der = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
  let raw = "";
  for (const b of der) raw += String.fromCharCode(b);
  return JSON.stringify({
    type: "service_account",
    project_id: "sagip-test",
    client_email: "sender@sagip-test.iam.gserviceaccount.com",
    private_key: `-----BEGIN PRIVATE KEY-----\n${btoa(raw)}\n-----END PRIVATE KEY-----\n`,
    token_uri: "https://oauth2.googleapis.com/token",
  });
})();
let handler: Handler | null = null;
(globalThis as Record<string, unknown>).Deno = {
  env: { get: (name: string) => env[name] },
  serve: (h: Handler) => {
    handler = h;
  },
};

interface Call {
  url: string;
  body: unknown;
}
let calls: Call[] = [];
let queue: unknown[] = [];
let rescues: unknown[] = [];
let rescueClaimStatus = 200;
let pushes: unknown[] = [];
/** FCM's answer per token (default: accepted). */
let fcmReplies: Record<string, { status: number; body: unknown }> = {};
let googleSignIn = 200;
const vaultKey = "vault-secret-for-the-tests-0123456789";
let recipients: string[] = [];
let left = 500;
let semaphoreStatus = 200;
let facebookStatus = 200;

globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = String(input);
  const raw = init?.body;
  const body = raw instanceof URLSearchParams
    ? Object.fromEntries(raw.entries())
    : raw
    ? JSON.parse(String(raw))
    : null;
  if (init?.headers && String(input).startsWith("https://fcm.googleapis.com/")) {
    assert.equal((init.headers as Record<string, string>).Authorization, "Bearer ya29.test");
  }
  calls.push({ url, body });
  const reply = (value: unknown, status = 200) =>
    new Response(value === null ? "" : JSON.stringify(value), { status });
  if (url.endsWith("/rpc/sender_secret")) return reply(vaultKey);
  if (url.endsWith("/rpc/claim_push_messages")) return reply(pushes);
  if (url.endsWith("/rpc/finish_push_message")) return reply(null, 204);
  if (url.endsWith("/rpc/forget_push_tokens")) return reply(1);
  if (url === "https://oauth2.googleapis.com/token") {
    return googleSignIn === 200
      ? reply({ access_token: "ya29.test", expires_in: 3599 })
      : reply({ error: "invalid_grant" }, googleSignIn);
  }
  if (url === "https://fcm.googleapis.com/v1/projects/sagip-test/messages:send") {
    const m = (body as { message: Record<string, unknown> }).message;
    const r = fcmReplies[String(m.token ?? m.topic ?? m.condition)];
    return r ? reply(r.body, r.status) : reply({ name: "projects/sagip-test/messages/1" });
  }
  if (url.endsWith("/rpc/claim_rescue_confirmations")) return reply(rescues, rescueClaimStatus);
  if (url.endsWith("/rpc/finish_rescue_confirmation")) return reply(null, 204);
  if (url.endsWith("/rpc/claim_alert_deliveries")) return reply(queue);
  if (url.endsWith("/rpc/alert_sms_recipients")) return reply(recipients);
  if (url.endsWith("/rpc/alert_sms_budget")) {
    return reply({ cap: 500, sent_today: 500 - left, left });
  }
  if (url.endsWith("/rpc/finish_alert_delivery")) return reply(null, 204);
  if (url.endsWith("/sms_log")) return reply(null, 201);
  if (url.startsWith("https://graph.facebook.com/")) {
    return facebookStatus === 200
      ? reply({ id: "1234_5678" })
      : reply({ error: { message: "Invalid OAuth access token.", code: 190 } }, facebookStatus);
  }
  if (url.startsWith("https://api.semaphore.co/")) {
    const numbers = String((body as Record<string, string>).number).split(",");
    return reply(
      numbers.map((recipient) => ({ recipient, status: "Pending" })),
      semaphoreStatus,
    );
  }
  throw new Error(`unexpected call to ${url}`);
}) as typeof fetch;

await import("./index.ts");

function call(key: string | null, body: unknown = {}): Promise<Response> {
  return handler!(
    new Request("https://project.example/functions/v1/send-alerts", {
      method: "POST",
      headers: key ? { "x-sagip-key": key } : {},
      body: JSON.stringify(body),
    }),
  );
}

function delivery(id: number, channel: string, alertId: string, endedAlready = false) {
  return {
    delivery_id: id,
    channel,
    alert: {
      alert_id: alertId,
      level: "warning",
      title: "Heavy rainfall warning",
      body: "PAGASA reports rain of 22 mm per hour over Manila. Flooding is possible in low-lying areas.",
      barangays: [] as string[],
      ended: endedAlready,
    },
  };
}

function finished(): Record<number, Record<string, unknown>> {
  const out: Record<number, Record<string, unknown>> = {};
  for (const c of calls) {
    if (c.url.endsWith("/rpc/finish_alert_delivery")) {
      const b = c.body as Record<string, unknown>;
      out[b.p_delivery_id as number] = b;
    }
  }
  return out;
}

function rescue(id: number, incidentId: string, to: string | null) {
  return {
    confirmation_id: id,
    incident_id: incidentId,
    kind: "assigned",
    unit_call_sign: "R-03",
    to,
  };
}

function rescued(): Record<number, Record<string, unknown>> {
  const out: Record<number, Record<string, unknown>> = {};
  for (const c of calls) {
    if (c.url.endsWith("/rpc/finish_rescue_confirmation")) {
      const b = c.body as Record<string, unknown>;
      out[b.p_confirmation_id as number] = b;
    }
  }
  return out;
}

function reset() {
  calls = [];
  queue = [];
  rescues = [];
  rescueClaimStatus = 200;
  pushes = [];
  fcmReplies = {};
  googleSignIn = 200;
  env.FIREBASE_SERVICE_ACCOUNT = undefined;
  recipients = [];
  left = 500;
  semaphoreStatus = 200;
  env.SEMAPHORE_API_KEY = "test-semaphore-key";
  env.FACEBOOK_PAGE_ID = undefined;
  env.FACEBOOK_PAGE_TOKEN = undefined;
  facebookStatus = 200;
}

test("a call without the shared secret does nothing", async () => {
  reset();
  queue = [delivery(1, "sms", "alert-a")];
  assert.equal((await call(null)).status, 401);
  assert.equal((await call("wrong-secret-for-the-tests")).status, 401);
  assert.equal(calls.length, 0, "nothing was read or sent");
});

test("an SMS alert is texted once to each resident and logged", async () => {
  reset();
  queue = [
    delivery(1, "sms", "alert-a"),
    delivery(2, "push", "alert-a"),
    delivery(3, "facebook", "alert-a"),
    delivery(4, "sms", "alert-old", true),
  ];
  recipients = ["+63 917 000 4821", "09170004821", "639180003310", "0285270000"];
  const res = await call(env.ALERTS_SECRET!);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {
    processed: 4,
    results: {
      "alert-a:sms": "sent",
      "alert-a:push": "notSetUp",
      "alert-a:facebook": "notSetUp",
      "alert-old:sms": "ended",
    },
  });

  const texts = calls.filter((c) => c.url.startsWith("https://api.semaphore.co/"));
  assert.equal(texts.length, 1, "one call for the batch; the ended alert is not sent");
  const form = texts[0].body as Record<string, string>;
  assert.equal(form.number, "09170004821,09180003310", "unique mobile numbers only");
  assert.ok(form.message.startsWith("S.A.G.I.P.: Heavy rainfall warning."));
  assert.ok(form.message.length <= 160);
  assert.equal(form.apikey, "test-semaphore-key");

  const log = calls.find((c) => c.url.endsWith("/sms_log"))!.body as Record<string, string>[];
  assert.deepEqual(
    log.map((r) => [r.kind, r.to_number, r.provider, r.status, r.detail]),
    [
      ["alert", "09170004821", "semaphore", "sent", "alert-a"],
      ["alert", "09180003310", "semaphore", "sent", "alert-a"],
    ],
  );

  const done = finished();
  assert.deepEqual(
    [done[1].p_status, done[1].p_recipients, done[1].p_delivered, done[1].p_failed],
    ["sent", 2, 2, 0],
  );
  assert.equal(done[2].p_status, "notSetUp");
  assert.equal(done[2].p_detail, "Push needs the Firebase project");
  assert.equal(done[4].p_status, "ended");
});

test("the daily cap leaves the rest unsent and says so", async () => {
  reset();
  queue = [delivery(5, "sms", "alert-b")];
  recipients = ["09170000001", "09170000002", "09170000003"];
  left = 2;
  await call(env.ALERTS_SECRET!);
  const form = calls.find((c) => c.url.startsWith("https://api.semaphore.co/"))!
    .body as Record<string, string>;
  assert.equal(form.number.split(",").length, 2);
  const done = finished()[5];
  assert.deepEqual(
    [done.p_status, done.p_recipients, done.p_delivered, done.p_failed, done.p_detail],
    ["sent", 3, 2, 1, "1 not sent: the daily limit was reached"],
  );
});

test("a refusal by Semaphore is a failed delivery, logged per number", async () => {
  reset();
  queue = [delivery(6, "sms", "alert-c")];
  recipients = ["09170000001"];
  semaphoreStatus = 401;
  await call(env.ALERTS_SECRET!);
  const done = finished()[6];
  assert.deepEqual([done.p_status, done.p_delivered, done.p_failed], ["failed", 0, 1]);
  const log = calls.find((c) => c.url.endsWith("/sms_log"))!.body as Record<string, string>[];
  assert.equal(log[0].status, "failed");
  assert.equal(log[0].detail, "alert-c: HTTP 401");
});

test("without a Semaphore key nothing is texted", async () => {
  reset();
  env.SEMAPHORE_API_KEY = undefined;
  queue = [delivery(7, "sms", "alert-d")];
  recipients = ["09170000001"];
  await call(env.ALERTS_SECRET!);
  assert.equal(calls.filter((c) => c.url.startsWith("https://api.semaphore.co/")).length, 0);
  assert.equal(finished()[7].p_status, "notSetUp");
  assert.equal(finished()[7].p_detail, "No Semaphore key");
});

test("nothing queued: nothing happens", async () => {
  reset();
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), { processed: 0, results: {} });
  assert.equal(calls.length, 3, "only the three claims; no Firebase sign-in");
});

test("a rescue confirmation is texted to its resident, before any alert", async () => {
  reset();
  rescues = [rescue(11, "INC-0147", "0917 000 4821"), rescue(12, "INC-0150", "8527-0000")];
  queue = [delivery(8, "sms", "alert-e")];
  recipients = ["09170000001"];
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), {
    processed: 3,
    results: { "INC-0147:assigned": "sent", "INC-0150:assigned": "failed", "alert-e:sms": "sent" },
  });

  const texts = calls.filter((c) => c.url.startsWith("https://api.semaphore.co/"));
  assert.equal(texts.length, 2, "one rescue text and one alert; the landline gets none");
  const form = texts[0].body as Record<string, string>;
  assert.equal(form.number, "09170004821");
  assert.equal(
    form.message,
    "S.A.G.I.P.: Rescue team R-03 has been sent to your location. Stay where you are if it is safe and keep your phone on. Ref INC-0147.",
  );
  assert.ok(form.message.length <= 160);
  assert.ok(
    calls.indexOf(texts[0]) < calls.findIndex((c) => c.url.endsWith("/rpc/claim_alert_deliveries")),
    "rescue texts go first",
  );

  const log = calls.find((c) => c.url.endsWith("/sms_log"))!.body as Record<string, string>;
  assert.deepEqual(
    [log.kind, log.to_number, log.provider, log.status, log.detail],
    ["rescue", "09170004821", "semaphore", "sent", "INC-0147"],
  );
  const done = rescued();
  assert.deepEqual([done[11].p_status, done[11].p_detail], ["sent", null]);
  assert.deepEqual([done[12].p_status, done[12].p_detail], ["failed", "No mobile number on record"]);
});

test("a rescue text Semaphore refuses is recorded as failed", async () => {
  reset();
  rescues = [rescue(13, "INC-0151", "09170004821")];
  semaphoreStatus = 500;
  await call(env.ALERTS_SECRET!);
  assert.deepEqual(
    [rescued()[13].p_status, rescued()[13].p_detail],
    ["failed", "HTTP 500"],
  );
  const log = calls.find((c) => c.url.endsWith("/sms_log"))!.body as Record<string, string>;
  assert.deepEqual([log.status, log.detail], ["failed", "INC-0151: HTTP 500"]);
});

test("without a Semaphore key a rescue text is marked not set up", async () => {
  reset();
  env.SEMAPHORE_API_KEY = undefined;
  rescues = [rescue(14, "INC-0152", "09170004821")];
  await call(env.ALERTS_SECRET!);
  assert.equal(calls.filter((c) => c.url.startsWith("https://api.semaphore.co/")).length, 0);
  assert.deepEqual(
    [rescued()[14].p_status, rescued()[14].p_detail],
    ["notSetUp", "No Semaphore key"],
  );
});

test("alerts still go out when the rescue queue cannot be read", async () => {
  reset();
  rescueClaimStatus = 404;
  queue = [delivery(9, "sms", "alert-f")];
  recipients = ["09170000001"];
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), { processed: 1, results: { "alert-f:sms": "sent" } });
});

function pushed(): Record<number, Record<string, unknown>> {
  const out: Record<number, Record<string, unknown>> = {};
  for (const c of calls) {
    if (c.url.endsWith("/rpc/finish_push_message")) {
      const b = c.body as Record<string, unknown>;
      out[b.p_message_id as number] = b;
    }
  }
  return out;
}

function fcmSends(): Record<string, unknown>[] {
  return calls
    .filter((c) => c.url.startsWith("https://fcm.googleapis.com/"))
    .map((c) => (c.body as { message: Record<string, unknown> }).message);
}

test("pushes go to each phone of the account; dead tokens are forgotten", async () => {
  reset();
  env.FIREBASE_SERVICE_ACCOUNT = firebaseKey;
  pushes = [
    {
      message_id: 21,
      kind: "rescue",
      title: "A rescue team is coming",
      body: "R-03 has been sent to your location. Stay where you are if it is safe.",
      data: { type: "rescue", incident_id: "INC-0152", confirmation_id: "7" },
      tokens: ["phone-a", "phone-b"],
    },
    {
      message_id: 22,
      kind: "assignment",
      title: "New assignment: INC-0152",
      body: "Flood · Barangay 412, Sampaloc. Open S.A.G.I.P. to accept.",
      data: { type: "assignment", incident_id: "INC-0152" },
      tokens: ["phone-gone"],
    },
  ];
  fcmReplies["phone-b"] = { status: 500, body: null };
  fcmReplies["phone-gone"] = {
    status: 404,
    body: { error: { details: [{ errorCode: "UNREGISTERED" }] } },
  };
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), {
    processed: 2,
    results: { "push:21:rescue": "sent", "push:22:assignment": "failed" },
  });

  const sends = fcmSends();
  assert.deepEqual(sends.map((m) => m.token), ["phone-a", "phone-b", "phone-gone"]);
  assert.deepEqual(sends[0].android, { priority: "high", notification: { channel_id: "sagip_rescue" } });
  assert.deepEqual((sends[2].android as Record<string, unknown>).notification, {
    channel_id: "sagip_assignments",
  });
  assert.equal(calls.filter((c) => c.url === "https://oauth2.googleapis.com/token").length, 1, "one sign-in per run");

  const done = pushed();
  assert.deepEqual(
    [done[21].p_status, done[21].p_devices, done[21].p_delivered, done[21].p_detail],
    ["sent", 2, 1, "HTTP 500"],
  );
  assert.deepEqual([done[22].p_status, done[22].p_delivered], ["failed", 0]);
  const forgot = calls.find((c) => c.url.endsWith("/rpc/forget_push_tokens"))!;
  assert.deepEqual(forgot.body, { p_tokens: ["phone-gone"] });
});

test("an alert push goes to its barangays' topics, or to all of Manila", async () => {
  reset();
  env.FIREBASE_SERVICE_ACCOUNT = firebaseKey;
  const everywhere = delivery(31, "push", "alert-all");
  const local = delivery(32, "push", "alert-local");
  local.alert.barangays = ["Barangay 412", "Barangay 490"];
  queue = [everywhere, local];
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), {
    processed: 2,
    results: { "alert-all:push": "sent", "alert-local:push": "sent" },
  });
  const sends = fcmSends();
  assert.equal(sends[0].topic, "manila");
  assert.equal(sends[1].condition, "'area-barangay-412' in topics || 'area-barangay-490' in topics");
  assert.deepEqual(sends[1].data, { type: "alert", alert_id: "alert-local" });
  assert.equal((sends[1].notification as Record<string, string>).title, "Heavy rainfall warning");
  assert.equal(finished()[31].p_status, "sent");
});

test("without the Firebase key pushes are marked not set up; a refused key fails them", async () => {
  reset();
  pushes = [{ message_id: 41, kind: "rescue", title: "T", body: "B", data: {}, tokens: ["phone-a"] }];
  queue = [delivery(42, "push", "alert-x")];
  await call(env.ALERTS_SECRET!);
  assert.equal(fcmSends().length, 0);
  assert.deepEqual([pushed()[41].p_status, pushed()[41].p_detail], ["notSetUp", "Push needs the Firebase project"]);
  assert.equal(finished()[42].p_status, "notSetUp");

  reset();
  env.FIREBASE_SERVICE_ACCOUNT = firebaseKey;
  googleSignIn = 401;
  pushes = [{ message_id: 43, kind: "rescue", title: "T", body: "B", data: {}, tokens: ["phone-a"] }];
  queue = [delivery(44, "push", "alert-y")];
  await call(env.ALERTS_SECRET!);
  assert.equal(fcmSends().length, 0);
  assert.deepEqual(
    [pushed()[43].p_status, pushed()[43].p_detail],
    ["failed", "Firebase sign-in refused (HTTP 401)"],
  );
  assert.deepEqual(
    [finished()[44].p_status, finished()[44].p_detail],
    ["failed", "Firebase sign-in refused (HTTP 401)"],
  );
});

test("without ALERTS_SECRET the database's vault secret is the key", async () => {
  reset();
  const saved = env.ALERTS_SECRET;
  env.ALERTS_SECRET = undefined;
  try {
    assert.equal((await call(saved!)).status, 401, "the old secret no longer opens it");
    const res = await call(vaultKey);
    assert.equal(res.status, 200);
    assert.ok(calls.some((c) => c.url.endsWith("/rpc/sender_secret")));
  } finally {
    env.ALERTS_SECRET = saved;
  }
});

test("a check reports what is set up and sends nothing", async () => {
  reset();
  env.SEMAPHORE_API_KEY = undefined;
  let res = await call(env.ALERTS_SECRET!, { check: true });
  assert.deepEqual(await res.json(), {
    firebase: "FIREBASE_SERVICE_ACCOUNT is not set",
    semaphore: "SEMAPHORE_API_KEY is not set",
    facebook: "FACEBOOK_PAGE_ID or FACEBOOK_PAGE_TOKEN is not set",
    secret: "ALERTS_SECRET",
  });

  env.FIREBASE_SERVICE_ACCOUNT = "export default {}";
  res = await call(env.ALERTS_SECRET!, { check: true });
  assert.equal(
    (await res.json()).firebase,
    "FIREBASE_SERVICE_ACCOUNT is set but is not a Firebase service account key file",
  );

  env.FIREBASE_SERVICE_ACCOUNT = firebaseKey;
  googleSignIn = 401;
  res = await call(env.ALERTS_SECRET!, { check: true });
  assert.equal((await res.json()).firebase, "Firebase sign-in refused (HTTP 401)");

  googleSignIn = 200;
  env.SEMAPHORE_API_KEY = "test-semaphore-key";
  res = await call(env.ALERTS_SECRET!, { check: true });
  assert.deepEqual(await res.json(), {
    firebase: "ready: signed in to project sagip-test",
    semaphore: "key set",
    facebook: "FACEBOOK_PAGE_ID or FACEBOOK_PAGE_TOKEN is not set",
    secret: "ALERTS_SECRET",
  });
  assert.ok(
    !calls.some((c) => /claim_/.test(c.url)),
    "a check claims nothing",
  );
});

test("with the Page token an alert is posted on Facebook; a refusal fails it", async () => {
  reset();
  env.FACEBOOK_PAGE_ID = "100200300";
  env.FACEBOOK_PAGE_TOKEN = "test-page-token";
  queue = [delivery(1, "facebook", "alert-a")];
  let res = await call(env.ALERTS_SECRET!);
  assert.deepEqual((await res.json()).results, { "alert-a:facebook": "sent" });
  const post = calls.find((c) => c.url.startsWith("https://graph.facebook.com/"))!;
  assert.equal(post.url, "https://graph.facebook.com/v24.0/100200300/feed");
  const form = post.body as Record<string, string>;
  assert.equal(form.access_token, "test-page-token");
  assert.ok(form.message.startsWith("[WARNING] Heavy rainfall warning\n\nPAGASA reports"));
  assert.ok(form.message.includes("Areas: All of Manila"));
  assert.equal(finished()[1].p_detail, "post 1234_5678");

  reset();
  env.FACEBOOK_PAGE_ID = "100200300";
  env.FACEBOOK_PAGE_TOKEN = "expired-page-token";
  facebookStatus = 400;
  queue = [delivery(2, "facebook", "alert-b")];
  res = await call(env.ALERTS_SECRET!);
  assert.deepEqual((await res.json()).results, { "alert-b:facebook": "failed" });
  assert.equal(
    finished()[2].p_detail,
    "Facebook refused the post (HTTP 400): Invalid OAuth access token.",
  );
});
