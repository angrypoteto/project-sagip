// road-conditions: TomTom's live jams, closed roads, and flooded roads in
// Manila for the dashboard map and routing (2026-11-25). The logic is in
// roads.ts.
//
// The database calls it every 5 minutes (migration road_conditions:
// pg_cron and pg_net) with the shared secret as `x-sagip-key`, the same
// secret send-alerts uses. The TomTom key is the secret TOMTOM_API_KEY; it
// is never logged or returned. Only road data is sent to TomTom (a box
// around Manila), never anyone's position.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy road-conditions --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import { incidentsUrl, roadItems } from "./roads.ts";

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

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not configured" });
  const key = await sharedSecret();
  if (!key || !authorized(req.headers, key)) {
    return json(401, { error: "not allowed" });
  }
  const tomtom = Deno.env.get("TOMTOM_API_KEY");
  if (!tomtom) return json(500, { error: "TOMTOM_API_KEY not set" });
  try {
    const res = await fetch(incidentsUrl(tomtom));
    if (!res.ok) {
      // The status only: TomTom's error text may echo the request.
      const why = `TomTom: HTTP ${res.status}`;
      await rpc("road_feed_failed", { p_message: why });
      return json(502, { error: why });
    }
    const items = roadItems(await res.json());
    const saved = await rpc<{ kept: number; dropped: number }>("save_road_conditions", {
      p_items: items,
      p_fetched_at: new Date().toISOString(),
    });
    console.log(`road-conditions: ${saved.kept} kept, ${saved.dropped} outside Manila`);
    return json(200, { status: "saved", ...saved });
  } catch (e) {
    const why = e instanceof Error ? e.message : String(e);
    await rpc("road_feed_failed", { p_message: why }).catch(() => {});
    return json(500, { error: why });
  }
});
