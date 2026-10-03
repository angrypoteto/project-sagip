// The live forecast's arithmetic: the trained LSTMs run forward on a
// replayed weather window, and the provisional rule (plan Q22) turns each
// probability and each barangay's KDE density into a risk level. Pure
// functions, tested with Node (forecast.test.ts) against Keras's own
// output for the same windows.
//
// The model file is supabase/data/forecast_live_v1.json, written by
// ml/forecast/export_live.py and kept in the `forecast_model` table.

export const hazards = ["flood", "fire", "storm_surge"] as const;
export type Hazard = typeof hazards[number];
export type Level = "low" | "moderate" | "high";

export interface LstmLayer {
  units: number;
  return_sequences: boolean;
  /** [inputs][4 * units], row-major; gates in Keras's order i, f, c, o. */
  kernel: number[];
  /** [units][4 * units]. */
  recurrent: number[];
  bias: number[];
}

export interface HazardModel {
  scaler_mean: number[];
  scaler_std: number[];
  /** The sixth feature: this hazard's incidents on the day before. */
  prior_day_incidents: number[];
  model: { layers: LstmLayer[]; dense: { weights: number[]; bias: number[] } };
  /** Relative KDE density per barangay (only those the rule can raise). */
  density: Record<string, number>;
}

export interface Threshold {
  probability: number;
  density: number;
}

export interface Rule {
  high: Threshold;
  moderate: Threshold[];
}

export interface LiveModel {
  version: string;
  window: number;
  horizon_hours: number;
  rule: Rule;
  /** One ISO date per replayed day. */
  days: string[];
  /** The five weather readings of each day. */
  weather: number[][];
  hazards: Record<Hazard, HazardModel>;
}

const sigmoid = (x: number) => 1 / (1 + Math.exp(-x));

/** One Keras LSTM layer (tanh, sigmoid gates, zero initial state). */
export function lstm(layer: LstmLayer, inputs: number[][]): number[][] {
  const n = layer.units;
  const width = 4 * n;
  const h = new Float64Array(n);
  const c = new Float64Array(n);
  const out: number[][] = [];
  for (const x of inputs) {
    const z = Float64Array.from(layer.bias);
    for (let i = 0; i < x.length; i++) {
      const xi = x[i];
      const row = i * width;
      for (let j = 0; j < width; j++) z[j] += xi * layer.kernel[row + j];
    }
    for (let k = 0; k < n; k++) {
      const hk = h[k];
      if (hk === 0) continue;
      const row = k * width;
      for (let j = 0; j < width; j++) z[j] += hk * layer.recurrent[row + j];
    }
    for (let j = 0; j < n; j++) {
      const input = sigmoid(z[j]);
      const forget = sigmoid(z[n + j]);
      const candidate = Math.tanh(z[2 * n + j]);
      const output = sigmoid(z[3 * n + j]);
      c[j] = forget * c[j] + input * candidate;
      h[j] = output * Math.tanh(c[j]);
    }
    out.push(Array.from(h));
  }
  return layer.return_sequences ? out : [out[out.length - 1]];
}

/** The six features of the [window] days ending on day [end]. */
export function windowAt(model: LiveModel, hazard: Hazard, end: number): number[][] {
  const prior = model.hazards[hazard].prior_day_incidents;
  const rows: number[][] = [];
  for (let d = end - model.window + 1; d <= end; d++) {
    rows.push([...model.weather[d], prior[d]]);
  }
  return rows;
}

/** The probability of at least one incident in the next 72 hours. */
export function probability(m: HazardModel, raw: number[][]): number {
  let seq = raw.map((row) => row.map((v, i) => (v - m.scaler_mean[i]) / m.scaler_std[i]));
  for (const layer of m.model.layers) seq = lstm(layer, seq);
  const last = seq[seq.length - 1];
  let z = m.model.dense.bias[0];
  for (let k = 0; k < last.length; k++) z += last[k] * m.model.dense.weights[k];
  return sigmoid(z);
}

/** PROVISIONAL (plan Q22): the same rule as run_forecast.risk_level. */
export function riskLevel(rule: Rule, p: number, density: number): Level {
  if (p >= rule.high.probability && density >= rule.high.density) return "high";
  if (rule.moderate.some((m) => p >= m.probability && density >= m.density)) {
    return "moderate";
  }
  return "low";
}

/**
 * The barangays that are not low on every hazard, each as three letters
 * (l, m, h) for flood, fire, and storm surge, as record_forecast_run
 * takes them. Every other barangay is low.
 */
export function levelCodes(
  model: LiveModel,
  probs: Record<Hazard, number>,
): Record<string, string> {
  const names = new Set<string>();
  for (const hz of hazards) {
    for (const name of Object.keys(model.hazards[hz].density)) names.add(name);
  }
  const letter: Record<Level, string> = { low: "l", moderate: "m", high: "h" };
  const out: Record<string, string> = {};
  for (const name of [...names].sort()) {
    const code = hazards
      .map((hz) => letter[riskLevel(model.rule, probs[hz], model.hazards[hz].density[name] ?? 0)])
      .join("");
    if (code !== "lll") out[name] = code;
  }
  return out;
}

/**
 * The replayed day for this run: [current] when it is a usable window end,
 * else the first one. The next run moves one day on and starts over after
 * the last day.
 */
export function replayDay(model: LiveModel, current: number | null): { day: number; next: number } {
  const first = model.window - 1;
  const last = model.days.length - 1;
  const day = current !== null && Number.isInteger(current) && current >= first && current <= last
    ? current
    : first;
  return { day, next: day >= last ? first : day + 1 };
}

/** One run: the probabilities and the level codes for the replayed day. */
export function forecastRun(model: LiveModel, current: number | null) {
  const { day, next } = replayDay(model, current);
  const probs = {} as Record<Hazard, number>;
  for (const hz of hazards) {
    probs[hz] = probability(model.hazards[hz], windowAt(model, hz, day));
  }
  return { windowEnd: model.days[day], probabilities: probs, levels: levelCodes(model, probs), next };
}
