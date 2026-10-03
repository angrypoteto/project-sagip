// ingest-pagasa: reads PAGASA's public pages every 10 minutes (FR5).
//
// PAGASA has no public API we can use in time (plan Q35), so this reads
// what it publishes: the NCR page's Heavy Rainfall Warning and the latest
// Tropical Cyclone Bulletin (a PDF), and records Manila's rainfall level,
// wind signal, and storm surge height (`record_pagasa_reading`). The
// threshold engine in the database raises or ends alerts from there. Each
// source's health goes to `feed_status` for the Weather page (D10). While
// simulation mode is on, readings are not recorded (the demo keeps its
// simulated weather); the feed status still is.
//
// The database calls it on a schedule (migration pagasa_feed: pg_cron and
// pg_net) with the shared secret as `x-sagip-key`, the same secret
// send-alerts uses (Supabase Vault, read through sender_secret()).
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy ingest-pagasa --no-verify-jwt

import { extractText, getDocumentProxy } from "npm:unpdf@1.8.1";
import { authorized } from "../sms-intake/intake.ts";
import { ingest, type IngestDeps, userAgent } from "./ingest.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function rpc<T>(name: string, params: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: serviceKey!,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(params),
  });
  if (!res.ok) throw new Error(`${name}: HTTP ${res.status}`);
  const text = await res.text();
  return (text ? JSON.parse(text) : null) as T;
}

let secret: Promise<string | null> | null = null;
function sharedSecret(): Promise<string | null> {
  const fromEnv = Deno.env.get("ALERTS_SECRET");
  if (fromEnv) return Promise.resolve(fromEnv);
  secret ??= rpc<string | null>("sender_secret").catch(() => {
    secret = null;
    return null;
  });
  return secret;
}

async function get(target: string): Promise<Response> {
  const res = await fetch(target, {
    headers: { "User-Agent": userAgent },
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`${new URL(target).pathname}: HTTP ${res.status}`);
  return res;
}

const deps: IngestDeps = {
  getText: async (u) => await (await get(u)).text(),
  getBytes: async (u) => new Uint8Array(await (await get(u)).arrayBuffer()),
  pdfText: async (bytes) => {
    const pdf = await getDocumentProxy(bytes);
    const { text } = await extractText(pdf, { mergePages: true });
    return text;
  },
  rpc,
};

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not configured" });
  const key = await sharedSecret();
  if (!key || !authorized(req.headers, key)) {
    return json(401, { error: "not allowed" });
  }
  try {
    return json(200, await ingest(deps));
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});
