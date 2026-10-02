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
let recipients: string[] = [];
let left = 500;
let semaphoreStatus = 200;

globalThis.fetch = (async (input: string | URL | Request, init?: RequestInit) => {
  const url = String(input);
  const raw = init?.body;
  const body = raw instanceof URLSearchParams
    ? Object.fromEntries(raw.entries())
    : raw
    ? JSON.parse(String(raw))
    : null;
  calls.push({ url, body });
  const reply = (value: unknown, status = 200) =>
    new Response(value === null ? "" : JSON.stringify(value), { status });
  if (url.endsWith("/rpc/claim_rescue_confirmations")) return reply(rescues, rescueClaimStatus);
  if (url.endsWith("/rpc/finish_rescue_confirmation")) return reply(null, 204);
  if (url.endsWith("/rpc/claim_alert_deliveries")) return reply(queue);
  if (url.endsWith("/rpc/alert_sms_recipients")) return reply(recipients);
  if (url.endsWith("/rpc/alert_sms_budget")) {
    return reply({ cap: 500, sent_today: 500 - left, left });
  }
  if (url.endsWith("/rpc/finish_alert_delivery")) return reply(null, 204);
  if (url.endsWith("/sms_log")) return reply(null, 201);
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

function call(key: string | null): Promise<Response> {
  return handler!(
    new Request("https://project.example/functions/v1/send-alerts", {
      method: "POST",
      headers: key ? { "x-sagip-key": key } : {},
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
      barangays: [],
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
  recipients = [];
  left = 500;
  semaphoreStatus = 200;
  env.SEMAPHORE_API_KEY = "test-semaphore-key";
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
  assert.equal(calls.length, 2, "only the two claims");
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
