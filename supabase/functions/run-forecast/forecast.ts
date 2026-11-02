// The live forecast's arithmetic: the trained LSTMs run forward on a
// replayed weather window, and the provisional rule (plan Q22) turns each
// probability and each barangay's KDE density into a risk level. Pure
// functions, tested with Node (forecast.test.ts) against Keras's own
// output for the same windows.
//
// The model file is supabase/data/forecast_live_v1.json, written by
// ml/forecast/heatmap/export_live.py and kept in the `forecast_model` table.

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

// ------------------------------------------------------------- live weather

/** Open-Meteo's answer, as run-forecast asks for it (Manila City Hall). */
export interface OpenMeteo {
  daily: {
    time: string[];
    precipitation_sum: (number | null)[];
    wind_speed_10m_max: (number | null)[];
  };
  hourly: { time: string[]; precipitation: (number | null)[] };
}

/** One day of SAGIP's own records (`forecast_live_days`). */
export interface RecordedDay {
  day: string;
  signal: number;
  surge_m: number;
  flood: number;
  fire: number;
}

/** [iso] (YYYY-MM-DD) moved [n] days. */
export function addDays(iso: string, n: number): string {
  const t = new Date(`${iso}T00:00:00Z`);
  t.setUTCDate(t.getUTCDate() + n);
  return t.toISOString().slice(0, 10);
}

export interface LiveWindow {
  days: string[];
  /** The five weather readings of each day, as model.weather. */
  weather: number[][];
  /** Each hazard's incidents on the day before each day. */
  prior: Record<Hazard, number[]>;
}

/**
 * The [model.window] days ending on [end] from live sources (2026-11-02),
 * built as the training data was (ml/forecast/data_prep/fetch_weather.py):
 * the day's rain, its wettest hour, and its strongest 10 m wind from
 * Open-Meteo; the highest PAGASA signal and storm surge in force that day,
 * and the day before's incidents, from SAGIP's records. SAGIP has no storm
 * surge incident type, so that count is 0. Null when a day is missing.
 */
export function liveWindow(
  model: LiveModel,
  om: OpenMeteo,
  recorded: RecordedDay[],
  end: string,
): LiveWindow | null {
  const days: string[] = [];
  for (let k = model.window - 1; k >= 0; k--) days.push(addDays(end, -k));
  const rainOf = new Map<string, number>();
  const windOf = new Map<string, number>();
  om.daily.time.forEach((d, i) => {
    const rain = om.daily.precipitation_sum[i];
    const wind = om.daily.wind_speed_10m_max[i];
    if (rain !== null && rain !== undefined) rainOf.set(d, rain);
    if (wind !== null && wind !== undefined) windOf.set(d, wind);
  });
  const wettest = new Map<string, number>();
  om.hourly.time.forEach((stamp, i) => {
    const mm = om.hourly.precipitation[i];
    if (mm === null || mm === undefined) return;
    const d = stamp.slice(0, 10);
    wettest.set(d, Math.max(wettest.get(d) ?? 0, mm));
  });
  const ours = new Map(recorded.map((r) => [r.day, r]));
  const weather: number[][] = [];
  const prior: Record<Hazard, number[]> = { flood: [], fire: [], storm_surge: [] };
  for (const d of days) {
    const rain = rainOf.get(d);
    const wind = windOf.get(d);
    const day = ours.get(d);
    const before = ours.get(addDays(d, -1));
    if (rain === undefined || wind === undefined || !day || !before) return null;
    weather.push([rain, wettest.get(d) ?? 0, day.signal, wind, day.surge_m]);
    prior.flood.push(before.flood);
    prior.fire.push(before.fire);
    prior.storm_surge.push(0);
  }
  return { days, weather, prior };
}

/** One run on a live window: the probabilities and the level codes. */
export function liveRun(model: LiveModel, win: LiveWindow) {
  const probs = {} as Record<Hazard, number>;
  for (const hz of hazards) {
    const rows = win.weather.map((w, i) => [...w, win.prior[hz][i]]);
    probs[hz] = probability(model.hazards[hz], rows);
  }
  return {
    windowEnd: win.days[win.days.length - 1],
    probabilities: probs,
    levels: levelCodes(model, probs),
  };
}
