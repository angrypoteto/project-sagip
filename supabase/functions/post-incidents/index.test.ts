// Run with: node --test supabase/functions/post-incidents/index.test.ts
//
// Runs the real handler in index.ts under Node, with Deno and the network
// replaced by stand-ins: the database calls and Facebook are recorded and
// answered here. Nothing is sent anywhere.
import { test } from "node:test";
import assert from "node:assert/strict";

type Handler = (req: Request) => Promise<Response>;

const env: Record<string, string | undefined> = {
  SUPABASE_URL: "https://project.example",
  SUPABASE_SERVICE_ROLE_KEY: "test-service-key",
  ALERTS_SECRET: "shared-secret-for-tests",
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
let claimStatus = 200;
let facebookStatus = 200;

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
  if (url.endsWith("/rpc/claim_incident_posts")) return reply(queue, claimStatus);
  if (url.endsWith("/rpc/record_incident_post")) return reply(null, 204);
  if (url.startsWith("https://graph.facebook.com/")) {
    if (facebookStatus !== 200) {
      return reply({ error: { message: "Invalid OAuth access token.", code: 190 } }, facebookStatus);
    }
    // A new post answers with its id; an edit of a post with success.
    return url.endsWith("/feed") ? reply({ id: "1234_5678" }) : reply({ success: true });
  }
  throw new Error(`unexpected request to ${url}`);
}) as typeof fetch;

await import("./index.ts");

function call(key: string | null, body: unknown = {}): Promise<Response> {
  return handler!(
    new Request("https://project.example/functions/v1/post-incidents", {
      method: "POST",
      headers: key ? { "x-sagip-key": key } : {},
      body: JSON.stringify(body),
    }),
  );
}

function reset() {
  calls = [];
  queue = [];
  claimStatus = 200;
  facebookStatus = 200;
  env.FACEBOOK_PAGE_ID = "100200300";
  env.FACEBOOK_PAGE_TOKEN = "test-page-token";
}

const words = "Confirmed fire in Pandacan.\n\nConfirmed at 2:14 PM, October 13, 2026.";
const claimed = [{ post_id: 7, incident_id: "INC-0200", message: words }];
const outcome = () =>
  calls.find((c) => c.url.endsWith("/rpc/record_incident_post"))?.body as
    | Record<string, unknown>
    | undefined;
const posted = () => calls.filter((c) => c.url.startsWith("https://graph.facebook.com/"));

test("without the shared secret nothing is read or posted", async () => {
  reset();
  queue = claimed;
  assert.equal((await call(null)).status, 401);
  assert.equal((await call("wrong-secret-of-same-length")).status, 401);
  assert.equal(calls.length, 0);
});

test("nothing queued: nothing happens", async () => {
  reset();
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), { processed: 0, results: {} });
  assert.equal(calls.length, 1, "only the claim");
});

test("a confirmed incident is posted with the database's words", async () => {
  reset();
  queue = claimed;
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual(await res.json(), { processed: 1, results: { "INC-0200": "sent" } });
  assert.equal(posted().length, 1);
  assert.equal(posted()[0].url, "https://graph.facebook.com/v24.0/100200300/feed");
  assert.deepEqual(posted()[0].body, { message: words, access_token: "test-page-token" });
  assert.deepEqual(outcome(), {
    p_post_id: 7,
    p_status: "sent",
    p_detail: "post 1234_5678",
    p_fb_post_id: "1234_5678",
    p_message: words,
  });
});

test("a post already on the Page is edited in place, not posted again", async () => {
  reset();
  const confirmed = "Confirmed fire in Pandacan.\n\nReported at 2:14 PM, October 16, confirmed at 2:20 PM.";
  queue = [{ post_id: 7, incident_id: "INC-0200", message: confirmed, fb_post_id: "1234_5678" }];
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual((await res.json()).results, { "INC-0200": "sent" });
  assert.equal(posted().length, 1);
  assert.equal(posted()[0].url, "https://graph.facebook.com/v24.0/1234_5678");
  assert.deepEqual(posted()[0].body, { message: confirmed, access_token: "test-page-token" });
  assert.deepEqual(outcome(), {
    p_post_id: 7,
    p_status: "sent",
    p_detail: "edited post 1234_5678",
    p_fb_post_id: "1234_5678",
    p_message: confirmed,
  });
});

test("a refusal from Facebook is recorded as failed, with why", async () => {
  reset();
  facebookStatus = 400;
  queue = claimed;
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual((await res.json()).results, { "INC-0200": "failed" });
  assert.deepEqual(outcome(), {
    p_post_id: 7,
    p_status: "failed",
    p_detail: "Facebook refused the post (HTTP 400): Invalid OAuth access token.",
    p_fb_post_id: null,
    p_message: words,
  });
});

test("with no Page or token it is recorded as not set up and nothing is sent", async () => {
  reset();
  env.FACEBOOK_PAGE_TOKEN = undefined;
  queue = claimed;
  const res = await call(env.ALERTS_SECRET!);
  assert.deepEqual((await res.json()).results, { "INC-0200": "notSetUp" });
  assert.equal(posted().length, 0);
  assert.equal(outcome()!.p_status, "notSetUp");
});

test("a queue that cannot be read is an error, and nothing is posted", async () => {
  reset();
  claimStatus = 500;
  const res = await call(env.ALERTS_SECRET!);
  assert.equal(res.status, 502);
  assert.equal(posted().length, 0);
});

test("a check says what is set up and claims nothing", async () => {
  reset();
  queue = claimed;
  let res = await call(env.ALERTS_SECRET!, { check: true });
  assert.deepEqual(await res.json(), { facebook: "page and token set", secret: "ALERTS_SECRET" });
  env.FACEBOOK_PAGE_ID = undefined;
  res = await call(env.ALERTS_SECRET!, { check: true });
  assert.equal((await res.json()).facebook, "FACEBOOK_PAGE_ID or FACEBOOK_PAGE_TOKEN is not set");
  assert.equal(calls.length, 0);
});
