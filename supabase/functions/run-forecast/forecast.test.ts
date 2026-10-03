// Run with: node --test supabase/functions/run-forecast/forecast.test.ts
//
// The model file holds Keras's own probability for a few windows; the
// TypeScript LSTM must give the same.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import {
  forecastRun,
  type Hazard,
  hazards,
  levelCodes,
  type LiveModel,
  probability,
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
