"""Data preparation for the LSTM half of the 72-hour forecast (FR4, plan
10.5): checks and cleans the two input files, lines them up as one record
per day, builds the 14-day input windows, splits them in time order, and
measures the baselines the LSTM has to beat.

It follows the thesis parameters (CLAUDE.md, "Algorithm parameters"):
  - six daily features: rainfall total, maximum hourly rainfall, highest
    typhoon signal, maximum wind, storm surge level, prior-day incident count
  - a 14-day window of them
  - the label: at least one incident in the next 72 hours
  - a chronological 70/15/15 split
  - class weights for the weighted binary cross-entropy

Three things the thesis leaves open are decided here PROVISIONALLY and are
marked so in the summary; the team must confirm them (plan Q21, Q22):
  - the forecast unit is the whole city (one series), one label per hazard
  - "prior-day incident count" on day d is the number of incidents of that
    hazard on day d - 1, so a window never holds the count of its last day
  - the three windows before each split point are dropped, because their
    labels look into the days of the next part

The LSTM itself is not trained here (TensorFlow is not installed on this
machine). This script writes the arrays it will train on.

Usage:
  python ml/forecast/prepare_windows.py
  python ml/forecast/prepare_windows.py --weather path.csv --incidents path.csv

Writes ml/forecast/build/windows_<hazard>.npz (git-ignored) and
ml/forecast/prep_summary.json.
"""

import argparse
import csv
import json
from datetime import date, timedelta
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
WINDOW = 14
HORIZON = 3  # days: "the next 72 hours"
SPLIT = (0.70, 0.15, 0.15)
HAZARDS = ("flood", "fire", "storm_surge")
FEATURES = (
    "rainfall_total_mm",
    "rainfall_max_hourly_mm",
    "typhoon_signal",
    "max_wind_kph",
    "storm_surge_m",
    "prior_day_incidents",
)
WEATHER_COLUMNS = FEATURES[:5]

# A box around the City of Manila with a small margin. Stands in for the
# barangay boundaries until the Data role delivers them.
MANILA_BOX = {"south": 14.53, "north": 14.66, "west": 120.93, "east": 121.04}

# What a daily weather record may hold; outside these it is a typing error.
WEATHER_RANGES = {
    "rainfall_total_mm": (0, 1500),
    "rainfall_max_hourly_mm": (0, 300),
    "typhoon_signal": (0, 5),
    "max_wind_kph": (0, 400),
    "storm_surge_m": (0, 10),
}


class DataError(ValueError):
    """The input files cannot be used as they are."""


def read_csv(path):
    with Path(path).open(newline="", encoding="utf-8-sig") as f:
        return list(csv.DictReader(f))


def parse_day(text):
    try:
        return date.fromisoformat((text or "").strip())
    except ValueError:
        return None


def load_weather(rows):
    """Daily weather as (days, values[n, 5]). Every day of the period must be
    there once and every value in range; anything else stops the run, because
    a silent gap would shift every window after it."""
    by_day = {}
    problems = []
    for n, r in enumerate(rows, start=2):  # line 1 is the header
        d = parse_day(r.get("date"))
        if d is None:
            problems.append(f"line {n}: unreadable date")
            continue
        if d in by_day:
            problems.append(f"line {n}: {d} appears twice")
            continue
        values = []
        for column in WEATHER_COLUMNS:
            low, high = WEATHER_RANGES[column]
            try:
                v = float(r[column])
            except (KeyError, TypeError, ValueError):
                problems.append(f"line {n}: {column} is missing or not a number")
                break
            if not low <= v <= high:
                problems.append(f"line {n}: {column} = {v} is outside {low} to {high}")
                break
            values.append(v)
        else:
            by_day[d] = values
    if by_day:
        first, last = min(by_day), max(by_day)
        d = first
        missing = 0
        while d <= last:
            if d not in by_day:
                missing += 1
                if missing <= 5:
                    problems.append(f"{d} has no weather record")
            d += timedelta(days=1)
        if missing > 5:
            problems.append(f"and {missing - 5} more days without a record")
    else:
        problems.append("no weather records")
    if problems:
        raise DataError("weather: " + "; ".join(problems[:12]))
    days = sorted(by_day)
    return days, np.array([by_day[d] for d in days], dtype=float)


def clean_incidents(rows, first_day, last_day):
    """Keeps the incident records that can be used and counts what was
    removed and why (plan 10.5: log how many were kept and removed)."""
    log = {
        "read": len(rows),
        "removed_unreadable_date": 0,
        "removed_outside_period": 0,
        "removed_unknown_hazard": 0,
        "removed_bad_coordinates": 0,
        "removed_outside_manila": 0,
        "removed_duplicates": 0,
        "kept": 0,
    }
    kept = []
    seen = set()
    for r in rows:
        d = parse_day(r.get("date"))
        if d is None:
            log["removed_unreadable_date"] += 1
            continue
        if not first_day <= d <= last_day:
            log["removed_outside_period"] += 1
            continue
        hazard = (r.get("hazard") or "").strip().lower().replace(" ", "_")
        if hazard not in HAZARDS:
            log["removed_unknown_hazard"] += 1
            continue
        try:
            lat, lng = float(r["latitude"]), float(r["longitude"])
        except (KeyError, TypeError, ValueError):
            log["removed_bad_coordinates"] += 1
            continue
        inside = (
            MANILA_BOX["south"] <= lat <= MANILA_BOX["north"]
            and MANILA_BOX["west"] <= lng <= MANILA_BOX["east"]
        )
        if not inside:
            log["removed_outside_manila"] += 1
            continue
        # The same hazard at the same spot on the same day is one incident
        # entered twice.
        key = (d, hazard, round(lat, 6), round(lng, 6))
        if key in seen:
            log["removed_duplicates"] += 1
            continue
        seen.add(key)
        kept.append({"date": d, "hazard": hazard, "latitude": lat, "longitude": lng})
    log["kept"] = len(kept)
    assert log["read"] == sum(v for k, v in log.items() if k != "read")
    return kept, log


def daily_counts(days, incidents, hazard):
    index = {d: i for i, d in enumerate(days)}
    counts = np.zeros(len(days), dtype=float)
    for r in incidents:
        if r["hazard"] == hazard:
            counts[index[r["date"]]] += 1
    return counts


def daily_features(weather, counts):
    """The six features of each day. The last one is the incident count of
    the day before; the first day has none and gets 0."""
    prior = np.concatenate([[0.0], counts[:-1]])
    return np.column_stack([weather, prior])


def labels(counts):
    """1 where at least one incident happens in the HORIZON days after day
    t. The last HORIZON days have no full horizon and get -1."""
    n = len(counts)
    out = np.full(n, -1, dtype=int)
    for t in range(n - HORIZON):
        out[t] = int(counts[t + 1 : t + 1 + HORIZON].sum() >= 1)
    return out


def build_windows(features, label):
    """X[i] is the WINDOW days ending on day ends[i]; y[i] is that day's
    label. The first day is skipped: its prior-day count is unknown."""
    n = len(features)
    ends = [t for t in range(WINDOW, n) if label[t] >= 0]
    x = np.stack([features[t - WINDOW + 1 : t + 1] for t in ends])
    y = np.array([label[t] for t in ends], dtype=int)
    return x, y, np.array(ends)


def split_in_time(count):
    """Index ranges of train, validation, and test, in time order, with the
    HORIZON windows before each split point dropped."""
    train_end = int(count * SPLIT[0])
    val_end = int(count * (SPLIT[0] + SPLIT[1]))
    return (
        (0, train_end - HORIZON),
        (train_end, val_end - HORIZON),
        (val_end, count),
    )


def fit_scaler(x_train):
    """Mean and spread of each feature over the training windows only, so
    nothing about later days leaks into the scaling."""
    flat = x_train.reshape(-1, x_train.shape[-1])
    mean = flat.mean(axis=0)
    std = flat.std(axis=0)
    std[std == 0] = 1.0
    return mean, std


def class_weights(y_train):
    """Weights for the weighted binary cross-entropy: each class counts the
    same in total. None when a class is missing from training."""
    n = len(y_train)
    positives = int(y_train.sum())
    negatives = n - positives
    if positives == 0 or negatives == 0:
        return None
    return {"0": round(n / (2 * negatives), 4), "1": round(n / (2 * positives), 4)}


def scores(y, probability, threshold=0.5):
    """Confusion-matrix accuracy and the rest (plan 10.5; RMSE for Q23)."""
    predicted = (np.asarray(probability) >= threshold).astype(int)
    tp = int(((predicted == 1) & (y == 1)).sum())
    tn = int(((predicted == 0) & (y == 0)).sum())
    fp = int(((predicted == 1) & (y == 0)).sum())
    fn = int(((predicted == 0) & (y == 1)).sum())
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "accuracy": round((tp + tn) / len(y), 4),
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "rmse": round(float(np.sqrt(np.mean((np.asarray(probability) - y) ** 2))), 4),
        "confusion": {"tp": tp, "fp": fp, "fn": fn, "tn": tn},
    }


def baselines(parts, feature_index):
    """What the LSTM must beat, on validation and test: always the more
    common class; "the last three days had an incident, so the next three
    will"; and logistic regression on the flattened window."""
    from sklearn.linear_model import LogisticRegression

    x_train, y_train = parts["train"]
    out = {}
    majority = int(y_train.mean() >= 0.5)
    prior = feature_index["prior_day_incidents"]
    model = None
    if 0 < y_train.sum() < len(y_train):
        model = LogisticRegression(class_weight="balanced", max_iter=2000, C=0.1)
        model.fit(x_train.reshape(len(x_train), -1), y_train)
    for name in ("validation", "test"):
        x, y = parts[name]
        if len(y) == 0:
            continue
        # Raw (unscaled) counts: was there an incident on any of the last
        # three days the window knows about?
        recent = parts["raw_" + name][:, -HORIZON:, prior].sum(axis=1) >= 1
        out[name] = {
            "positives": int(y.sum()),
            "windows": int(len(y)),
            "always_majority": scores(y, np.full(len(y), float(majority))),
            "persistence": scores(y, recent.astype(float)),
        }
        if model is not None:
            p = model.predict_proba(x.reshape(len(x), -1))[:, 1]
            out[name]["logistic_regression"] = scores(y, p)
    return out


def prepare(weather_rows, incident_rows, out_dir=None):
    """Runs the whole preparation and returns the summary."""
    days, weather = load_weather(weather_rows)
    incidents, log = clean_incidents(incident_rows, days[0], days[-1])
    summary = {
        "provisional": [
            "forecast unit: the whole city, one label per hazard (plan Q21, Q22)",
            "prior-day incident count on day d = incidents of that hazard on day d - 1",
            f"the {HORIZON} windows before each split point are dropped",
        ],
        "window_days": WINDOW,
        "horizon_days": HORIZON,
        "split": list(SPLIT),
        "features": list(FEATURES),
        "period": [days[0].isoformat(), days[-1].isoformat()],
        "days": len(days),
        "incident_records": log,
        "hazards": {},
    }
    index = {name: i for i, name in enumerate(FEATURES)}
    for hazard in HAZARDS:
        counts = daily_counts(days, incidents, hazard)
        x_raw, y, ends = build_windows(daily_features(weather, counts), labels(counts))
        ranges = dict(zip(("train", "validation", "test"), split_in_time(len(y))))
        mean, std = fit_scaler(x_raw[slice(*ranges["train"])])
        x = (x_raw - mean) / std
        parts = {}
        for name, (a, b) in ranges.items():
            parts[name] = (x[a:b], y[a:b])
            parts["raw_" + name] = x_raw[a:b]
        y_train = parts["train"][1]
        weights = class_weights(y_train)
        summary["hazards"][hazard] = {
            "incidents": int(counts.sum()),
            "days_with_an_incident": int((counts > 0).sum()),
            "windows": int(len(y)),
            "parts": {
                name: {
                    "windows": int(b - a),
                    "positives": int(y[a:b].sum()),
                    "positive_rate": round(float(y[a:b].mean()), 4) if b > a else None,
                    "first_window_ends": days[int(ends[a])].isoformat() if b > a else None,
                    "last_window_ends": days[int(ends[b - 1])].isoformat() if b > a else None,
                }
                for name, (a, b) in ranges.items()
            },
            "class_weights": weights,
            "scaler": {"mean": [round(float(v), 4) for v in mean], "std": [round(float(v), 4) for v in std]},
            "baselines": baselines(parts, index),
        }
        if out_dir is not None:
            Path(out_dir).mkdir(parents=True, exist_ok=True)
            np.savez_compressed(
                Path(out_dir) / f"windows_{hazard}.npz",
                x_train=parts["train"][0], y_train=parts["train"][1],
                x_val=parts["validation"][0], y_val=parts["validation"][1],
                x_test=parts["test"][0], y_test=parts["test"][1],
                scaler_mean=mean, scaler_std=std,
                class_weight=np.array([weights["0"], weights["1"]]) if weights else np.array([1.0, 1.0]),
            )
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--weather", default=HERE / "data" / "sample_weather_daily.csv")
    parser.add_argument("--incidents", default=HERE / "data" / "sample_incidents.csv")
    args = parser.parse_args()
    sample = "sample_" in Path(args.weather).name or "sample_" in Path(args.incidents).name
    summary = prepare(read_csv(args.weather), read_csv(args.incidents), out_dir=HERE / "build")
    summary = {
        "data": "SAMPLE (made up by make_sample_data.py); nothing here is a result" if sample else "as given",
        **summary,
    }
    (HERE / "prep_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

    log = summary["incident_records"]
    print(f"{summary['days']} days, {log['kept']} of {log['read']} incident records kept")
    for hazard, h in summary["hazards"].items():
        p = h["parts"]
        line = ", ".join(f"{name} {p[name]['windows']} ({p[name]['positive_rate']})" for name in p)
        test = h["baselines"].get("test", {})
        best = test.get("logistic_regression", {}).get("f1")
        print(f"  {hazard}: {line}; class weights {h['class_weights']}; test F1 of the logistic baseline {best}")


if __name__ == "__main__":
    main()
