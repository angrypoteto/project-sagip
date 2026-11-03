// ingest-phivolcs: reads PHIVOLCS's list of recent earthquakes every 15
// minutes and keeps the ones near Manila for the Weather page (FR14).
//
// Earthquakes are an advisory relay only (CLAUDE.md scope: no earthquake
// forecasting). Since 2026-11-03 (FR14) record_phivolcs_events passes the
// ones felt in Manila (A3: magnitude and distance) on to residents by
// itself, as informational alerts in the app and by push (migration
// phivolcs_relay); the dispatcher may relay any other from D10. It also
// reads every volcano's alert level from PHIVOLCS's bulletin list
// (record_volcano_levels, migration phivolcs_volcano); a change of Taal or
// Pinatubo is passed on with ashfall guidance. A failure there is noted in
// the feed status and never stops the earthquakes.
// The feed's health goes to feed_status (source `phivolcs`).
//
// The database calls it on a schedule (migration phivolcs_feed: pg_cron
// and pg_net) with the shared secret as `x-sagip-key`, the same secret
// send-alerts uses.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy ingest-phivolcs --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import { nearManila, parseEarthquakes, parseVolcanoLevels, phivolcsPage, volcanoPage } from "./phivolcs.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

/** A clear name for PHIVOLCS's logs; two requests per run (earthquakes, volcanoes). */
const userAgent =
  "SAGIP-MDRRMD/1.0 (Manila City emergency response capstone; reads the public earthquake list and volcano alert levels every 15 minutes)";

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

/** The volcano alert levels (FR14); never throws. */
async function volcanoLevels(): Promise<Record<string, unknown>> {
  try {
    const res = await fetch(volcanoPage, {
      headers: { "User-Agent": userAgent },
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) throw new Error(`volcano page: HTTP ${res.status}`);
    const levels = parseVolcanoLevels(await res.text());
    if (levels.length === 0) throw new Error("No alert levels on the volcano page");
    const relayed = await rpc<number>("record_volcano_levels", { p_levels: levels });
    return {
      volcanoes: Object.fromEntries(levels.map((v) => [v.volcano, v.level])),
      volcano_notices: relayed,
    };
  } catch (e) {
    return { volcano_error: (e instanceof Error ? e.message : String(e)).slice(0, 200) };
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not configured" });
  const key = await sharedSecret();
  if (!key || !authorized(req.headers, key)) {
    return json(401, { error: "not allowed" });
  }
  try {
    const res = await fetch(phivolcsPage, {
      headers: { "User-Agent": userAgent },
      signal: AbortSignal.timeout(45_000),
    });
    if (!res.ok) throw new Error(`PHIVOLCS page: HTTP ${res.status}`);
    const all = parseEarthquakes(await res.text());
    if (all.length === 0) throw new Error("No earthquake rows on the PHIVOLCS page");
    const near = nearManila(all, new Date());
    const added = await rpc<number>("record_phivolcs_events", {
      p_events: near.map((q) => ({
        key: q.key,
        occurred_at: q.occurredAt,
        latitude: q.latitude,
        longitude: q.longitude,
        depth_km: q.depthKm,
        magnitude: q.magnitude,
        location: q.location,
        distance_km: q.distanceKm,
        bulletin_url: q.bulletinUrl,
      })),
    });
    const volcano = await volcanoLevels();
    await rpc("record_feed_status", {
      p_source: "phivolcs",
      p_ok: true,
      p_error: null,
      p_seen: {
        events: all.length,
        near_manila: near.length,
        newest: all[0]?.occurredAt ?? null,
        ...volcano,
      },
    });
    return json(200, { status: "ok", events: all.length, near_manila: near.length, added, ...volcano });
  } catch (e) {
    const error = (e instanceof Error ? e.message : String(e)).slice(0, 300);
    await rpc("record_feed_status", {
      p_source: "phivolcs",
      p_ok: false,
      p_error: error,
      p_seen: null,
    }).catch(() => {});
    return json(502, { error });
  }
});
