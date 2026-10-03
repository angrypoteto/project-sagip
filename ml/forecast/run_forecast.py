"""One run of the 72-hour forecast (FR4): the LSTM's probability for the
city and the KDE's density per barangay, turned into a risk level per
barangay and hazard, as rows for `barangay_forecast` (D8 and R8 read them).

Inputs:
  - build/lstm_<hazard>.keras and build/windows_<hazard>.npz (the scaler)
    from train_lstm.py and prepare_windows.py;
  - kde_summary.json from kde.py (relative density per barangay, 897);
  - the last 14 days of the weather file, ending on --as-of (default: the
    file's last day). This is the "simulated live feed" of the thesis
    scope: the weather records are replayed as if they were today's.

PROVISIONAL (plan Q22, the team decides): how the probability and the
density become a level. The rule is in `risk_level` and nowhere else:
  - high:     probability >= 0.50 and relative density >= 0.50
  - moderate: probability >= 0.50 and relative density >= 0.20,
              or probability >= 0.25 and relative density >= 0.50
  - low:      anything else
"Relative density" is the barangay's mean density divided by the densest
barangay's, for that hazard (kde.py).

Writes forecast_run.json (the probabilities, the rule, counts per level;
kept in git) and build/forecast_insert.sql (git-ignored): one statement
that adds the run for every barangay in the database (barangays not named
are low). Run it in the Supabase SQL editor.

Usage (TensorFlow is in .venv-tf):
  ../../.venv-tf/Scripts/python run_forecast.py
  ../../.venv-tf/Scripts/python run_forecast.py --as-of 2025-08-21
"""

import argparse
import datetime as dt
import json
from pathlib import Path

import numpy as np

from prepare_windows import (
    FEATURES,
    HAZARDS,
    WINDOW,
    clean_incidents,
    daily_counts,
    daily_features,
    load_weather,
    read_csv,
)

HERE = Path(__file__).parent
BUILD = HERE / "build"
MODEL_VERSION = "lstm-kde-v1 (sample data, provisional levels)"
DB_HAZARD = {"flood": "flood_risk", "fire": "fire_risk", "storm_surge": "surge_risk"}


# PROVISIONAL (plan Q22): the thresholds of `risk_level`. The live feed
# (export_live.py, the run-forecast Edge Function) reads the same numbers.
RULE = {
    "high": {"probability": 0.5, "density": 0.5},
    "moderate": [
        {"probability": 0.5, "density": 0.2},
        {"probability": 0.25, "density": 0.5},
    ],
}


def risk_level(probability, relative_density):
    """PROVISIONAL (plan Q22): see the module docstring."""
    hi = RULE["high"]
    if probability >= hi["probability"] and relative_density >= hi["density"]:
        return "high"
    if any(
        probability >= m["probability"] and relative_density >= m["density"]
        for m in RULE["moderate"]
    ):
        return "moderate"
    return "low"


def window_ending(days, features, as_of):
    """The WINDOW days of features ending on as_of, as in prepare_windows."""
    if as_of not in days:
        raise SystemExit(f"{as_of} is not in the weather file ({days[0]} to {days[-1]})")
    end = days.index(as_of)
    if end < WINDOW:
        raise SystemExit(f"{as_of} needs {WINDOW} days of weather before it")
    return features[end - WINDOW + 1 : end + 1]


def probabilities(as_of, weather_path, incidents_path):
    """The LSTM's probability of at least one incident in the next 72
    hours, per hazard, for the window ending on as_of."""
    import tensorflow as tf  # only here, so the rest imports without it

    days, weather = load_weather(read_csv(weather_path))
    incidents, _ = clean_incidents(read_csv(incidents_path), days[0], days[-1])
    out = {}
    for hazard in HAZARDS:
        data = np.load(BUILD / f"windows_{hazard}.npz")
        raw = window_ending(days, daily_features(weather, daily_counts(days, incidents, hazard)), as_of)
        x = (raw - data["scaler_mean"]) / data["scaler_std"]
        model = tf.keras.models.load_model(BUILD / f"lstm_{hazard}.keras")
        out[hazard] = float(model.predict(x[np.newaxis, ...], verbose=0).ravel()[0])
    return out


def run(probs, kde_summary):
    """{barangay: {hazard: level}} for every barangay the KDE scored."""
    levels = {}
    for hazard in HAZARDS:
        scored = kde_summary["hazards"].get(hazard, {}).get("barangays", {})
        for name, b in scored.items():
            levels.setdefault(name, {})[hazard] = risk_level(probs[hazard], b["relative"])
    return levels


def insert_sql(levels, issued_at):
    """One statement: every barangay in the database gets a row; the ones
    named here get their levels, the rest are low."""
    letter = {"low": "l", "moderate": "m", "high": "h"}
    named = [
        (name, "".join(letter[lv.get(h, "low")] for h in HAZARDS))
        for name, lv in sorted(levels.items())
        if any(v != "low" for v in lv.values())
    ]
    values = ",\n  ".join(f"('{name}', '{code}')" for name, code in named) or "(null, null)"
    word = "case substr(coalesce(v.code, 'lll'), {i}, 1) when 'h' then 'high' when 'm' then 'moderate' else 'low' end"
    return f"""-- Forecast run made by ml/forecast/run_forecast.py ({MODEL_VERSION}).
insert into public.barangay_forecast
  (barangay, district, issued_at, valid_until, flood_risk, fire_risk, surge_risk, model_version, is_simulated)
select b.name, b.district, timestamptz '{issued_at}', timestamptz '{issued_at}' + interval '72 hours',
       {word.format(i=1)},
       {word.format(i=2)},
       {word.format(i=3)},
       '{MODEL_VERSION}', true
  from public.barangay b
  left join (values
  {values}
  ) as v(name, code) on v.name = b.name;
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--weather", default=HERE / "data" / "sample_weather_daily.csv")
    parser.add_argument("--incidents", default=HERE / "data" / "sample_incidents.csv")
    parser.add_argument("--as-of", default=None, help="the window's last day, YYYY-MM-DD")
    parser.add_argument("--issued-at", default=None, help="ISO time for the run (default: now)")
    args = parser.parse_args()

    days, _ = load_weather(read_csv(args.weather))
    as_of = dt.date.fromisoformat(args.as_of) if args.as_of else days[-1]
    probs = probabilities(as_of, args.weather, args.incidents)
    kde_summary = json.loads((HERE / "kde_summary.json").read_text(encoding="utf-8"))
    levels = run(probs, kde_summary)
    issued_at = args.issued_at or dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()

    counts = {
        h: {lv: sum(1 for b in levels.values() if b.get(h) == lv) for lv in ("high", "moderate", "low")}
        for h in HAZARDS
    }
    summary = {
        "data": "SAMPLE (made up by make_sample_data.py); nothing here is a result",
        "model_version": MODEL_VERSION,
        "window_ends": as_of.isoformat(),
        "features": list(FEATURES),
        "probability_next_72h": {h: round(p, 4) for h, p in probs.items()},
        "provisional_rule": risk_level.__doc__.strip() + " high: p>=0.5 and density>=0.5; "
        "moderate: p>=0.5 and density>=0.2, or p>=0.25 and density>=0.5; else low",
        "barangays": len(levels),
        "levels": counts,
    }
    (HERE / "forecast_run.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    BUILD.mkdir(exist_ok=True)
    (BUILD / "forecast_insert.sql").write_text(insert_sql(levels, issued_at), encoding="utf-8")
    print(json.dumps(summary["probability_next_72h"]), json.dumps(counts))


if __name__ == "__main__":
    main()
