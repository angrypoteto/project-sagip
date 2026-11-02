// run-forecast: the live feed of the 72-hour forecast (FR4; thesis scope:
// "LSTM and KDE trained, simulated live feed").
//
// Since 2026-11-02 it runs on live weather: the 14 days to yesterday from
// Open-Meteo (Manila City Hall) and SAGIP's own records
// (`forecast_live_days`: PAGASA signal and storm surge, incidents), built as
// the training data was. If a source fails it falls back to the replay
// below and says so in the run's model version.
//
// Every few hours the database calls this (migration forecast_live: pg_cron
// and pg_net, with the same shared secret as send-alerts). It reads the
// active model and the replay position (`forecast_live_input`), runs the
// three LSTMs on the 14 replayed days ending there, turns each probability
// and each barangay's KDE density into a risk level by the provisional rule
// (plan Q22), and records the run for every barangay
// (`record_forecast_run_labelled`), which moves the replay one day on. D8
// and the resident's forecast tab show the newest run; a replayed run is
// marked simulated and names the replayed day in its model version, a live
// one names the last day of its window.
//
// The model is the sample one (made-up data): nothing it says is a result.
//
// Deploy with JWT checking off (the shared secret is the check):
//   supabase functions deploy run-forecast --no-verify-jwt

import { authorized } from "../sms-intake/intake.ts";
import {
  addDays,
  forecastRun,
  liveRun,
  liveWindow,
  type LiveModel,
  type OpenMeteo,
  type RecordedDay,
  replayDay,
} from "./forecast.ts";

const OPEN_METEO = "https://api.open-meteo.com/v1/forecast?latitude=14.5995&longitude=120.9842" +
  "&daily=precipitation_sum,wind_speed_10m_max&hourly=precipitation&wind_speed_unit=kmh" +
  "&timezone=Asia%2FManila&past_days=16&forecast_days=1";

/** Yesterday in Manila (UTC+8), the last whole day of the window. */
function manilaYesterday(): string {
  return new Date(Date.now() + 8 * 3600e3 - 86400e3).toISOString().slice(0, 10);
}

/** The run on live weather, or the reason it could not be made. */
async function live(model: LiveModel) {
  const end = manilaYesterday();
  const [om, recorded] = await Promise.all([
    fetch(OPEN_METEO).then(async (r) => {
      if (!r.ok) throw new Error(`Open-Meteo: HTTP ${r.status}`);
      return await r.json() as OpenMeteo;
    }),
    rpc<RecordedDay[]>("forecast_live_days", {
      p_from: addDays(end, -model.window),
      p_to: end,
    }),
  ]);
  const win = liveWindow(model, om, recorded, end);
  if (!win) throw new Error("a day of the window is missing");
  return liveRun(model, win);
}

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
    let mode = "live";
    let run: { windowEnd: string; probabilities: Record<string, number>; levels: Record<string, string>; next: number };
    let label: string | null;
    try {
      const r = await live(input.model);
      // The replay stays where it was, for the next fallback.
      run = { ...r, next: replayDay(input.model, input.day_index).day };
      label = `live weather, 14 days to ${r.windowEnd} (sample-trained model, provisional levels)`;
    } catch (e) {
      mode = `replay (${e instanceof Error ? e.message : String(e)})`;
      run = forecastRun(input.model, input.day_index);
      label = null;
    }
    const recorded = await rpc<number>("record_forecast_run_labelled", {
      p_version: input.version,
      p_window_end: run.windowEnd,
      p_probabilities: run.probabilities,
      p_levels: run.levels,
      p_next_index: run.next,
      p_label: label,
      p_simulated: label === null,
    });
    console.log(
      `run-forecast: ${mode}, window to ${run.windowEnd}, ${Object.keys(run.levels).length} barangays above low`,
    );
    return json(200, {
      status: "recorded",
      mode,
      window_end: run.windowEnd,
      probabilities: run.probabilities,
      barangays: recorded,
    });
  } catch (e) {
    return json(500, { error: e instanceof Error ? e.message : String(e) });
  }
});
