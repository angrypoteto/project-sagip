// Run with: node --test supabase/functions/run-forecast/forecast.test.ts
//
// The model file holds Keras's own probability for a few windows; the
// TypeScript LSTM must give the same.
import { test } from "node:test";
import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import {
  addDays,
  forecastHazards,
  forecastRun,
  type Hazard,
  hazards,
  levelCodes,
  liveRun,
  liveWindow,
  type LiveModel,
  type OpenMeteo,
  probability,
  type RecordedDay,
  replayDay,
  riskLevel,
  windowAt,
} from "./forecast.ts";

const file = new URL("../../data/forecast_live_v1.json", import.meta.url);
const model = JSON.parse(readFileSync(file, "utf8")) as LiveModel & {
  test_vectors: { hazard: Hazard; window_end: string; probability: number }[];
};

test("the LSTM matches Keras on the exported windows", () => {
  assert.equal(model.test_vectors.length, 9);
  for (const v of model.test_vectors) {
    const end = model.days.indexOf(v.window_end);
    const p = probability(model.hazards[v.hazard], windowAt(model, v.hazard, end));
    assert.ok(
      Math.abs(p - v.probability) < 1e-5,
      `${v.hazard} ${v.window_end}: ${p} against Keras ${v.probability}`,
    );
  }
});

test("a window is 14 days of six features ending on the day", () => {
  const end = model.days.indexOf("2024-07-02");
  const w = windowAt(model, "flood", end);
  assert.equal(w.length, 14);
  assert.ok(w.every((row) => row.length === 6));
  assert.deepEqual(w[13].slice(0, 5), model.weather[end]);
  assert.equal(w[13][5], model.hazards.flood.prior_day_incidents[end]);
});

test("the provisional rule, as in run_forecast.py", () => {
  const r = model.rule;
  assert.equal(riskLevel(r, 0.5, 0.5), "high");
  assert.equal(riskLevel(r, 0.5, 0.2), "moderate");
  assert.equal(riskLevel(r, 0.25, 0.5), "moderate");
  assert.equal(riskLevel(r, 0.49, 0.49), "low");
  assert.equal(riskLevel(r, 0.9, 0.1), "low");
});

test("only barangays above low on some hazard get a code", () => {
  const codes = levelCodes(model, { flood: 0.6, fire: 0.3, storm_surge: 0 });
  for (const [name, code] of Object.entries(codes)) {
    assert.match(code, /^[lmh]{3}$/);
    assert.notEqual(code, "lll", name);
    assert.equal(code[2], "l", "no surge risk at probability 0");
  }
  assert.deepEqual(levelCodes(model, { flood: 0, fire: 0, storm_surge: 0 }), {});
});

test("the replay moves one day a run and starts over at the end", () => {
  const first = model.window - 1;
  const last = model.days.length - 1;
  assert.deepEqual(replayDay(model, null), { day: first, next: first + 1 });
  assert.deepEqual(replayDay(model, 3), { day: first, next: first + 1 }, "too early for a window");
  assert.deepEqual(replayDay(model, 500), { day: 500, next: 501 });
  assert.deepEqual(replayDay(model, last), { day: last, next: first });
  assert.deepEqual(replayDay(model, last + 5), { day: first, next: first + 1 });
});

test("a whole run: three probabilities and the codes", () => {
  const end = model.days.indexOf("2025-12-31");
  const run = forecastRun(model, end);
  assert.equal(run.windowEnd, "2025-12-31");
  for (const hz of hazards) {
    assert.ok(run.probabilities[hz] >= 0 && run.probabilities[hz] <= 1);
  }
  const fire = model.test_vectors.find((v) => v.hazard === "fire" && v.window_end === "2025-12-31")!;
  assert.ok(Math.abs(run.probabilities.fire - fire.probability) < 1e-5);
  assert.equal(run.next, model.window - 1, "the last day wraps around");
  assert.ok(Object.keys(run.levels).length > 0, "fire at 66% raises some barangays");
});

// ------------------------------------------------------------- live weather

/** Open-Meteo and SAGIP records that hold the replayed days [from..to]:
 * each day's wettest hour as one hour, the rest dry. */
function sourcesFor(from: number, to: number): { om: OpenMeteo; recorded: RecordedDay[] } {
  const om: OpenMeteo = {
    daily: { time: [], precipitation_sum: [], wind_speed_10m_max: [] },
    hourly: { time: [], precipitation: [] },
  };
  const recorded: RecordedDay[] = [];
  for (let d = from; d <= to; d++) {
    const day = model.days[d];
    const [rain, wettest, signal, wind, surge] = model.weather[d];
    om.daily.time.push(day);
    om.daily.precipitation_sum.push(rain);
    om.daily.wind_speed_10m_max.push(wind);
    for (let h = 0; h < 24; h++) {
      om.hourly.time.push(`${day}T${String(h).padStart(2, "0")}:00`);
      om.hourly.precipitation.push(h === 12 ? wettest : 0);
    }
    // prior_day_incidents[d + 1] is the count of day d.
    recorded.push({
      day,
      signal,
      surge_m: surge,
      flood: model.hazards.flood.prior_day_incidents[d + 1] ?? 0,
      fire: model.hazards.fire.prior_day_incidents[d + 1] ?? 0,
    });
  }
  return { om, recorded };
}

test("a live window is built as the training data was", () => {
  const end = model.days.indexOf("2024-07-02");
  const { om, recorded } = sourcesFor(end - 14, end);
  const win = liveWindow(model, om, recorded, "2024-07-02")!;
  assert.equal(win.days.length, 14);
  assert.equal(win.days[13], "2024-07-02");
  assert.equal(win.days[0], addDays("2024-07-02", -13));
  for (let i = 0; i < 14; i++) {
    const d = end - 13 + i;
    assert.deepEqual(win.weather[i], model.weather[d]);
    assert.equal(win.prior.flood[i], model.hazards.flood.prior_day_incidents[d]);
    assert.equal(win.prior.storm_surge[i], 0, "no storm surge incident type");
  }
});

test("on live inputs the LSTM still matches Keras", () => {
  for (const v of model.test_vectors.filter((t) => t.hazard !== "storm_surge")) {
    const end = model.days.indexOf(v.window_end);
    const { om, recorded } = sourcesFor(end - 14, end);
    const run = liveRun(model, liveWindow(model, om, recorded, v.window_end)!);
    assert.ok(
      Math.abs(run.probabilities[v.hazard] - v.probability) < 1e-5,
      `${v.hazard} ${v.window_end}: ${run.probabilities[v.hazard]} against Keras ${v.probability}`,
    );
    assert.equal(run.windowEnd, v.window_end);
  }
});

test("a missing day gives no live window", () => {
  const end = model.days.indexOf("2024-07-02");
  const { om, recorded } = sourcesFor(end - 14, end);
  assert.equal(liveWindow(model, om, recorded.slice(1), "2024-07-02"), null, "no record of the day before");
  om.daily.precipitation_sum[5] = null;
  const fresh = sourcesFor(end - 14, end).recorded;
  assert.equal(liveWindow(model, om, fresh, "2024-07-02"), null, "no rain for a day");
});

// The live forecast's model (lstm-kde-v2, 2026-11-02): trained on the
// recorded 2021 to 2026 data, flood and fire only, no replay days.
const v2File = new URL("../../data/forecast_live_v2.json", import.meta.url);
const v2 = existsSync(v2File)
  ? JSON.parse(readFileSync(v2File, "utf8")) as LiveModel & {
    test_vectors: { hazard: Hazard; window: number[][]; probability: number }[];
  }
  : null;

test("v2: the LSTM matches Keras on windows from the test period", { skip: !v2 }, () => {
  assert.ok(v2!.test_vectors.length >= 4);
  for (const v of v2!.test_vectors) {
    const p = probability(v2!.hazards[v.hazard]!, v.window);
    assert.ok(Math.abs(p - v.probability) < 1e-5, `${v.hazard}: ${p} against Keras ${v.probability}`);
  }
});

test("v2: storm surge is not forecast, so it is low everywhere", { skip: !v2 }, () => {
  assert.deepEqual(forecastHazards(v2!), ["flood", "fire"]);
  assert.equal(v2!.days.length, 0);
  const codes = levelCodes(v2!, { flood: 1, fire: 1 });
  assert.ok(Object.values(codes).every((c) => c.length === 3 && c[2] === "l"));
});

// Model v3 (lstm-kde-v3, 2026-11-07): MDRRMD's own fire and flood records,
// a 48-hour lead time, flood and fire only.
const v3File = new URL("../../data/forecast_live_v3.json", import.meta.url);
const v3 = existsSync(v3File)
  ? JSON.parse(readFileSync(v3File, "utf8")) as LiveModel & {
    test_vectors: { hazard: Hazard; window: number[][]; probability: number }[];
  }
  : null;

test("v3: the LSTM matches Keras on windows from the test period", { skip: !v3 }, () => {
  assert.ok(v3!.test_vectors.length >= 4);
  for (const v of v3!.test_vectors) {
    const p = probability(v3!.hazards[v.hazard]!, v.window);
    assert.ok(Math.abs(p - v.probability) < 1e-5, `${v.hazard}: ${p} against Keras ${v.probability}`);
  }
});

test("v3: a 48-hour lead time, flood and fire", { skip: !v3 }, () => {
  assert.equal(v3!.horizon_hours, 48);
  assert.deepEqual(forecastHazards(v3!), ["flood", "fire"]);
  assert.equal(v3!.days.length, 0);
});
