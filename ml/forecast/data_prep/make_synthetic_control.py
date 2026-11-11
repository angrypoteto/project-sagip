"""Objective 2 control experiment: SYNTHETIC incidents on REAL weather.

Why: on MDRRMD's real records the flood heatmap passes 80% but the fire
heatmap cannot, because Manila's fires are not driven by the weather the
LSTM reads (docs/OBJECTIVE-2-RESULTS.md, sections 9 to 12). This experiment
asks the other half of the question: when incidents DO follow the weather,
does the same pipeline (the thesis's LSTM, KDE, and heatmap rule, unchanged)
learn it and reach the 80% target? If it does, the method is sound and the
real result is a limit of the records, not of the system.

Nothing here is a result about Manila. The weather is real (ERA5 via
Open-Meteo, 2021-01-01 to 2026-10-05, the same file the live model's
preparation uses); the incidents are INVENTED by the rules below, placed in
barangays in proportion to where MDRRMD's real incidents cluster (the
MDRRMD KDE), so the map looks like Manila's.

The invented rules (written down so they can be shown to the panel):
  flood on day d: P = logistic(-7.0 + 0.08 * rain over days d-7..d-1 (mm)
                               + 1.5 * highest signal on day d-1)
                  then 1 to 5 flooded places (Poisson, mean 2)
  fire on day d:  P = logistic(-6.0 + 0.6 * dry days before d (capped at 20)
                               + 0.1 * (wind on day d-1 - 13 kph))
                  then 1 or 2 fires
Each depends only on days before d. The pattern is clear on purpose (a
first try with gentler rules, P rarely above 0.3, was mostly noise: even a
forecaster that knew the rules could not have predicted it). The summary
gives that perfect forecaster's score as the ceiling to compare with.

Usage (from ml/forecast):
  ../../.venv/Scripts/python data_prep/make_synthetic_control.py
  ../../.venv-tf/Scripts/python lstm/train_lstm.py --prep data_prep/prep_summary_synthetic.json \
      --build build/real/synthetic --out lstm/lstm_metrics_synthetic.json
  ../../.venv-tf/Scripts/python heatmap/evaluate_heatmap.py --variant synthetic

Writes data/prepared/synthetic/ (weather and the invented incidents),
build/real/synthetic/windows_<hazard>.npz, and
data_prep/prep_summary_synthetic.json.
"""

import csv
import json
import math
import sys
from datetime import date
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
FORECAST = HERE.parent
sys.path.insert(0, str(FORECAST))

from lstm.prepare_windows import (  # noqa: E402
    FEATURES,
    WINDOW,
    WEATHER_COLUMNS,
    baselines,
    class_weights,
    daily_features,
    fit_scaler,
    labels,
    read_csv,
    split_in_time,
)

SEED = 20261112
WEATHER = FORECAST / "data" / "prepared" / "recorded" / "manila_weather_prepared.csv"
KDE = FORECAST / "kde" / "kde_summary_mdrrmd.json"
BARANGAYS = FORECAST.parent.parent / "supabase" / "data" / "manila_barangays.csv"
OUT = FORECAST / "data" / "prepared" / "synthetic"
BUILD = FORECAST / "build" / "real" / "synthetic"

RULES = {
    "flood": "P = logistic(-7.0 + 0.08 * rain over days d-7..d-1 (mm) + 1.5 * highest signal on day d-1); "
             "1 to 5 places (Poisson, mean 2)",
    "fire": "P = logistic(-6.0 + 0.6 * dry days before d (capped at 20) + 0.1 * (wind on day d-1 - 13 kph)); "
            "1 or 2 fires",
}


def logistic(z):
    return 1.0 / (1.0 + math.exp(-z))


def main():
    rng = np.random.default_rng(SEED)
    weather_rows = read_csv(WEATHER)
    days = [date.fromisoformat(r["date"]) for r in weather_rows]
    w = np.array([[float(r[c]) for c in WEATHER_COLUMNS] for r in weather_rows])
    rain, signal, wind = w[:, 0], w[:, 2], w[:, 3]

    kde = json.loads(KDE.read_text(encoding="utf-8"))["hazards"]
    centres = {
        r["name"]: (float(r["center_latitude"]), float(r["center_longitude"]))
        for r in read_csv(BARANGAYS)
    }

    def placer(hazard):
        rel = {n: b["relative"] for n, b in kde[hazard]["barangays"].items() if n in centres}
        names = list(rel)
        weights = np.array([rel[n] ** 2 for n in names])
        return names, weights / weights.sum()

    places = {h: placer(h) for h in ("flood", "fire")}

    incidents = []
    dry = 0
    chance = {"flood": np.zeros(len(days)), "fire": np.zeros(len(days))}
    for i, d in enumerate(days):
        if i >= 7:
            rain7 = float(rain[i - 7 : i].sum())
            p_flood = logistic(-7.0 + 0.08 * rain7 + 1.5 * float(signal[i - 1]))
            p_fire = logistic(-6.0 + 0.6 * min(dry, 20) + 0.1 * (float(wind[i - 1]) - 13))
            chance["flood"][i], chance["fire"][i] = p_flood, p_fire
            for hazard, p, count in (
                ("flood", p_flood, lambda: min(5, 1 + rng.poisson(1.0))),
                ("fire", p_fire, lambda: 1 + int(rng.random() < 0.3)),
            ):
                if rng.random() < p:
                    names, prob = places[hazard]
                    for _ in range(count()):
                        n = names[rng.choice(len(names), p=prob)]
                        lat, lng = centres[n]
                        incidents.append({
                            "incident_id": f"synthetic-{hazard}-{len(incidents) + 1}",
                            "date": d.isoformat(),
                            "hazard": hazard,
                            "latitude": round(lat + rng.normal(0, 0.0008), 5),
                            "longitude": round(lng + rng.normal(0, 0.0008), 5),
                            "precision": "point",
                            "barangay": n,
                            "use_for_kde": "yes",
                            "source_url": "SYNTHETIC (make_synthetic_control.py)",
                        })
        # Dry days before the next day: reset by a wet day (>= 1 mm).
        dry = 0 if rain[i] >= 1 else dry + 1

    OUT.mkdir(parents=True, exist_ok=True)
    BUILD.mkdir(parents=True, exist_ok=True)
    for path, rows, fields in (
        (OUT / "manila_weather_prepared.csv", weather_rows, list(weather_rows[0].keys())),
        (OUT / "manila_incidents_prepared.csv", incidents,
         ["incident_id", "date", "hazard", "latitude", "longitude", "precision", "barangay",
          "use_for_kde", "source_url"]),
    ):
        with path.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)

    summary = {
        "variant": "synthetic",
        "data": "SYNTHETIC CONTROL: real Manila weather (ERA5) 2021-01-01 to 2026-10-05 with INVENTED incidents "
                "that follow written rules (make_synthetic_control.py). Not a result about Manila; it tests "
                "whether the pipeline learns a weather pattern when one exists.",
        "rules": RULES,
        "seed": SEED,
        "window_days": WINDOW,
        "horizon_days": 3,
        "split": [0.7, 0.15, 0.15],
        "features": list(FEATURES),
        "period": [days[0].isoformat(), days[-1].isoformat()],
        "hazards": {},
    }
    for hazard in ("flood", "fire"):
        counts = np.zeros(len(days))
        index = {d.isoformat(): i for i, d in enumerate(days)}
        for r in incidents:
            if r["hazard"] == hazard:
                counts[index[r["date"]]] += 1
        features = daily_features(w, counts)
        label = labels(counts)
        ends_i = [t for t in range(WINDOW, len(days)) if label[t] >= 0]
        x_raw = np.stack([features[t - WINDOW + 1 : t + 1] for t in ends_i])
        y = np.array([label[t] for t in ends_i], dtype=int)
        ends = [days[t].isoformat() for t in ends_i]
        ranges = dict(zip(("train", "validation", "test"), split_in_time(len(y))))
        mean, std = fit_scaler(x_raw[slice(*ranges["train"])])
        x = (x_raw - mean) / std
        parts = {}
        for name, (a, b) in ranges.items():
            parts[name] = (x[a:b], y[a:b])
            parts["raw_" + name] = x_raw[a:b]
        weights = class_weights(parts["train"][1])
        np.savez_compressed(
            BUILD / f"windows_{hazard}.npz",
            x_train=parts["train"][0], y_train=parts["train"][1],
            x_val=parts["validation"][0], y_val=parts["validation"][1],
            x_test=parts["test"][0], y_test=parts["test"][1],
            scaler_mean=mean, scaler_std=std,
            class_weight=np.array([weights["0"], weights["1"]]),
            ends=np.array(ends),
            ranges=np.array([ranges[k] for k in ("train", "validation", "test")]),
        )
        # The ceiling: a forecaster that knows the rules and the next three
        # days' weather, saying "yes" when the 72-hour chance is 0.5 or more.
        a, b = ranges["test"]
        oracle = np.array([
            1 - np.prod(1 - chance[hazard][t + 1 : t + 4]) >= 0.5 for t in ends_i
        ])[a:b]
        truth = y[a:b].astype(bool)
        tp, tn = int((oracle & truth).sum()), int((~oracle & ~truth).sum())
        pos, neg = int(truth.sum()), int((~truth).sum())
        ceiling = {
            "accuracy": round((tp + tn) / len(truth), 4),
            "balanced_accuracy": round(((tp / pos if pos else 0) + (tn / neg if neg else 0)) / 2, 4),
            "recall": round(tp / pos, 4) if pos else 0.0,
        }
        summary["hazards"][hazard] = {
            "perfect_forecaster_on_test": ceiling,
            "incident_records": int(counts.sum()),
            "days_with_an_incident": int((counts > 0).sum()),
            "windows": int(len(y)),
            "parts": {
                name: {
                    "windows": int(b - a),
                    "positives": int(y[a:b].sum()),
                    "positive_rate": round(float(y[a:b].mean()), 4),
                    "first_window_ends": ends[a],
                    "last_window_ends": ends[b - 1],
                }
                for name, (a, b) in ranges.items()
            },
            "class_weights": weights,
            "baselines": baselines(parts, {n: i for i, n in enumerate(FEATURES)}),
        }
        print(hazard, int(counts.sum()), "incidents on", int((counts > 0).sum()), "days;",
              {k: v["positive_rate"] for k, v in summary["hazards"][hazard]["parts"].items()},
              "ceiling", ceiling)
    (HERE / "prep_summary_synthetic.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
