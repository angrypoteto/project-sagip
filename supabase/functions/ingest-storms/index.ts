// ingest-storms: the typhoon tracker's feeds, every 30 minutes (2026-11-02).
//
// Reads GDACS's tropical cyclones of the last 60 days (the UN and EU's
// Global Disaster Alert and Coordination System, from JTWC advisories) and
// keeps those whose track touches the Philippine Area of Responsibility,
// with their wind zones and forecast cone; and reads PAGASA's public CAP
// feed (tropical cyclone warnings with their wind signal, general flood
// advisories with their areas), fetching only the alerts it has not saved
// yet. Both go to `save_hazard_feeds`. If GDACS cannot be read the storms
// are left as they were; if PAGASA cannot be read, no warnings are added.
//
// The database calls it on a schedule (migration storm_tracker: pg_cron and
// pg_net) with the shared secret as `x-sagip-key`, as run-forecast.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy ingest-storms --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import { candidates, capWarning, type Feature, feedEntries, stormFrom, type WarningRow } from "./parse.ts";

const GDACS = "https://www.gdacs.org/gdacsapi/api";
const PAGASA_FEED = "https://publicalert.pagasa.dost.gov.ph/feeds/";
const userAgent = "SAGIP/1.0 (Manila MDRRMD emergency platform; +https://sagip.me)";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

const serviceHeaders = () => ({
  apikey: serviceKey!,
  Authorization: `Bearer ${serviceKey}`,
  "Content-Type": "application/json",
});

async function rpc<T>(name: string, params: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: serviceHeaders(),
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
  if (!res.ok) throw new Error(`${new URL(target).host}${new URL(target).pathname}: HTTP ${res.status}`);
  return res;
}

const day = (d: Date) => d.toISOString().slice(0, 10);

/** The cyclones touching PAR; throws if any part cannot be read. */
async function storms() {
  const now = new Date();
  const from = new Date(now.getTime() - 60 * 86400e3);
  const list = await (await get(
    `${GDACS}/events/geteventlist/SEARCH?eventlist=TC&fromdate=${day(from)}&todate=${day(now)}`,
  )).json() as { features?: Feature[] };
  const found = await Promise.all(candidates(list).map(async (f) => {
    const p = f.properties;
    const geometry = await (await get(
      `${GDACS}/polygons/getgeometry?eventtype=TC&eventid=${p.eventid}&episodeid=${p.episodeid}`,
    )).json() as { features?: Feature[] };
    return stormFrom(p, geometry);
  }));
  return found.filter((s) => s !== null);
}

/** The alerts in PAGASA's feed from the last 7 days not saved yet. */
async function warnings(): Promise<WarningRow[]> {
  const since = Date.now() - 7 * 86400e3;
  const entries = feedEntries(await (await get(PAGASA_FEED)).text())
    .filter((e) => new Date(e.updated).getTime() >= since && /^[0-9a-f-]{36}$/i.test(e.id));
  if (!entries.length) return [];
  const res = await fetch(
    `${url}/rest/v1/pagasa_warning?select=id&id=in.(${entries.map((e) => e.id).join(",")})`,
    { headers: serviceHeaders() },
  );
  if (!res.ok) throw new Error(`pagasa_warning: HTTP ${res.status}`);
  const known = new Set((await res.json() as { id: string }[]).map((r) => r.id));
  const fresh = entries.filter((e) => !known.has(e.id)).slice(0, 40);
  const out: WarningRow[] = [];
  // A few at a time, to go easy on PAGASA's server.
  for (let i = 0; i < fresh.length; i += 5) {
    const batch = await Promise.all(fresh.slice(i, i + 5).map(async (e) => {
      try {
        return capWarning(await (await get(e.href)).text(), e.kind);
      } catch {
        return null; // Tried again on the next run.
      }
    }));
    for (const w of batch) if (w) out.push(w);
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not configured" });
  const key = await sharedSecret();
  if (!key || !authorized(req.headers, key)) {
    return json(401, { error: "not allowed" });
  }
  const errors: string[] = [];
  const [s, w] = await Promise.all([
    storms().catch((e) => {
      errors.push(`GDACS: ${e instanceof Error ? e.message : String(e)}`);
      return null;
    }),
    warnings().catch((e) => {
      errors.push(`PAGASA: ${e instanceof Error ? e.message : String(e)}`);
      return [] as WarningRow[];
    }),
  ]);
  try {
    const saved = await rpc<{ storms: number; warnings: number }>("save_hazard_feeds", {
      p_storms: s,
      p_warnings: w,
    });
    console.log(`ingest-storms: ${saved.storms} storms, ${saved.warnings} new warnings${errors.length ? `; ${errors.join("; ")}` : ""}`);
    return json(200, {
      status: errors.length ? "partial" : "ok",
      storms: s?.map((x) => `${x.name} (${x.is_current ? "current" : "past"})`) ?? null,
      saved,
      errors,
    });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e), errors });
  }
});
