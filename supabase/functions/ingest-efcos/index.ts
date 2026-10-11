// ingest-efcos: reads PAGASA's public river level list for the
// Pasig-Marikina-Tullahan basin every 10 minutes for the Weather page (FR5).
//
// Nothing reaches residents by itself: the dispatcher sees the levels on
// D10 and may relay a level as an advisory.
// The feed's health goes to feed_status (source `efcos`).
//
// The database calls it on a schedule (migration river_levels: pg_cron
// and pg_net) with the shared secret as `x-sagip-key`, the same secret
// send-alerts uses.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy ingest-efcos --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import { levelState, parseLevels, riverPage } from "./efcos.ts";
import { pagasaIntermediate } from "./intermediate.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

/** A clear name for PAGASA's logs; one request per run. */
const userAgent =
  "SAGIP-MDRRMD/1.0 (Manila City emergency response capstone; reads the public river level list every 10 minutes)";

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
  try {
    // PAGASA's server leaves out its intermediate certificate (see
    // intermediate.ts); this client knows it, for this request only.
    const client = Deno.createHttpClient({ caCerts: [pagasaIntermediate] });
    let body: string;
    try {
      const res = await fetch(riverPage, {
        headers: { "User-Agent": userAgent },
        signal: AbortSignal.timeout(30_000),
        client,
      } as RequestInit);
      if (!res.ok) throw new Error(`PAGASA river list: HTTP ${res.status}`);
      body = await res.text();
    } finally {
      client.close();
    }
    const levels = parseLevels(body);
    if (levels.length === 0) throw new Error("No stations on the PAGASA river list");
    await rpc("record_river_levels", {
      p_levels: levels.map((l) => ({
        code: l.code,
        name: l.name,
        latitude: l.latitude,
        longitude: l.longitude,
        observed_at: l.observedAt,
        level_m: l.levelM,
        change_m: l.changeM,
        alert_m: l.alertM,
        alarm_m: l.alarmM,
        critical_m: l.criticalM,
        flagged: l.flagged,
      })),
    });
    const stations = levels.length;
    const raised = levels.filter((l) => {
      const state = levelState(l);
      return state === "alert" || state === "alarm" || state === "critical";
    }).length;
    const newest = levels.map((l) => l.observedAt).sort().at(-1) ?? null;
    await rpc("record_feed_status", {
      p_source: "efcos",
      p_ok: true,
      p_error: null,
      p_seen: { stations, raised, newest },
    });
    return json(200, { status: "ok", stations, raised });
  } catch (e) {
    const error = (e instanceof Error ? e.message : String(e)).slice(0, 300);
    await rpc("record_feed_status", {
      p_source: "efcos",
      p_ok: false,
      p_error: error,
      p_seen: null,
    }).catch(() => {});
    return json(502, { error });
  }
});
