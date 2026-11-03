// purge-photos: deletes the files of expired incident photos from the
// incident-photos bucket (NFR4, RA 10173; 2026-11-03). The retention job
// hides a photo once its incident is anonymized (expired_at); this deletes
// the file itself, which SQL cannot do. The logic is in purge.ts.
//
// The database calls it daily (migration photo_file_cleanup: pg_cron and
// pg_net, 30 minutes after apply-retention) with the shared secret as
// `x-sagip-key`, the same secret send-alerts uses. Nothing is logged about
// who took a photo; the response counts files only.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy purge-photos --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import { type ExpiredFile, purgeExpired } from "./purge.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const bucket = "incident-photos";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function serviceHeaders(): Record<string, string> {
  return {
    apikey: serviceKey!,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

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

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not configured" });
  const key = await sharedSecret();
  if (!key || !authorized(req.headers, key)) {
    return json(401, { error: "not allowed" });
  }
  try {
    const result = await purgeExpired({
      list: (limit) => rpc<ExpiredFile[]>("expired_photo_files", { p_limit: limit }),
      remove: async (paths) => {
        const res = await fetch(`${url}/storage/v1/object/${bucket}`, {
          method: "DELETE",
          headers: serviceHeaders(),
          body: JSON.stringify({ prefixes: paths }),
        });
        if (!res.ok) throw new Error(`storage delete: HTTP ${res.status}`);
      },
      mark: (ids) => rpc<number>("mark_photo_files_removed", { p_photo_ids: ids }),
    });
    return json(200, { status: "ok", ...result });
  } catch (e) {
    const error = (e instanceof Error ? e.message : String(e)).slice(0, 300);
    return json(502, { error });
  }
});
