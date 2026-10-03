// run-forecast: the simulated live feed of the 72-hour forecast (FR4;
// thesis scope: "LSTM and KDE trained, simulated live feed").
//
// Every few hours the database calls this (migration forecast_live: pg_cron
// and pg_net, with the same shared secret as send-alerts). It reads the
// active model and the replay position (`forecast_live_input`), runs the
// three LSTMs on the 14 replayed days ending there, turns each probability
// and each barangay's KDE density into a risk level by the provisional rule
// (plan Q22), and records the run for every barangay
// (`record_forecast_run`), which moves the replay one day on. D8 and the
// resident's forecast tab show the newest run; its rows are marked
// simulated and name the replayed day in the model version.
//
// The model is the sample one (made-up data): nothing it says is a result.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy run-forecast --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import { forecastRun, type LiveModel } from "./forecast.ts";

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

interface Input {
  version: string;
  model: LiveModel;
  day_index: number | null;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "POST only" });
  if (!url || !serviceKey) return json(500, { error: "not configured" });
  const key = await sharedSecret();
  if (!key || !authorized(req.headers, key)) {
    return json(401, { error: "not allowed" });
  }
  try {
    const input = await rpc<Input | null>("forecast_live_input");
    if (!input) return json(200, { status: "no model loaded" });
    const run = forecastRun(input.model, input.day_index);
    const recorded = await rpc<number>("record_forecast_run", {
      p_version: input.version,
      p_window_end: run.windowEnd,
      p_probabilities: run.probabilities,
      p_levels: run.levels,
      p_next_index: run.next,
    });
    console.log(
      `run-forecast: ${run.windowEnd} replayed, ${Object.keys(run.levels).length} barangays above low`,
    );
    return json(200, {
      status: "recorded",
      window_end: run.windowEnd,
      probabilities: run.probabilities,
      barangays: recorded,
    });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});
