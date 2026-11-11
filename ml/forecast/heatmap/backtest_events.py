"""Backtests the live forecast's model on named past events (Objective 2's
evidence for the defense, 2026-11-02): for each event day, the chance the
model gives of at least one incident in the next 72 hours from the 14 days
before it, next to what the records hold for those 72 hours.

It is the same computation run-forecast makes every six hours, only the 14
days come from the records instead of this week's weather. The events are
named in EVENTS (PAGASA's names, the dates the news reported Manila flooding
or a big fire); the rest of each table comes from the data.

Usage (TensorFlow is in .venv-tf), after export_live.py --variant recorded:
  ../../.venv-tf/Scripts/python heatmap/backtest_events.py [--variant recorded]

Writes heatmap/backtest_<variant>.json and prints a table.
"""

import argparse
import json
import sys
from datetime import date, timedelta
from pathlib import Path

import numpy as np

FORECAST = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(FORECAST))

from lstm.prepare_windows import WINDOW, read_csv  # noqa: E402

# The day the forecast is made (its window ends the day before).
EVENTS = [
    ("flood", "Carina (Gaemi) and the southwest monsoon", date(2024, 7, 24)),
    ("flood", "Enteng (Yagi)", date(2024, 9, 2)),
    ("flood", "Kristine (Trami)", date(2024, 10, 24)),
    ("flood", "Southwest monsoon, July 2025", date(2025, 7, 21)),
    ("flood", "A dry-season day (control)", date(2025, 3, 10)),
]


def main():
    import tensorflow as tf

    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default="recorded")
    # The weather can come from a longer file than the model's own records,
    # to replay events from before them (2026-11-12: model v4, trained on
    # MDRRMD's records from December 2024, on the 2024 typhoons it never saw;
    # its prior-day incident count is 0 before MDRRMD's records begin).
    parser.add_argument("--weather-from", default=None)
    args = parser.parse_args()
    prepared = FORECAST / "data" / "prepared" / args.variant
    build = FORECAST / "build" / "real" / args.variant
    weather_dir = FORECAST / "data" / "prepared" / (args.weather_from or args.variant)

    weather_rows = read_csv(weather_dir / "manila_weather_prepared.csv")
    days = [date.fromisoformat(r["date"]) for r in weather_rows]
    columns = ["rainfall_total_mm", "rainfall_max_hourly_mm", "typhoon_signal", "max_wind_kph", "storm_surge_m"]
    weather = np.array([[float(r[c]) for c in columns] for r in weather_rows])
    index = {d: i for i, d in enumerate(days)}
    incidents = read_csv(prepared / "manila_incidents_prepared.csv")

    def count(hazard, day):
        return sum(1 for r in incidents if r["hazard"] == hazard and r["date"] == day.isoformat())

    # The two highest-fire days in the records join the fire events.
    fire_days = {}
    for r in incidents:
        if r["hazard"] == "fire":
            fire_days[r["date"]] = fire_days.get(r["date"], 0) + 1
    busiest = sorted(fire_days.items(), key=lambda kv: -kv[1])[:2]
    events = EVENTS + [("fire", f"Busiest fire day in the records ({n} fires)", date.fromisoformat(d))
                       for d, n in busiest]
    events.append(("fire", "A day with no fire recorded in the next 72 hours (control)", None))

    models, scalers = {}, {}
    for hazard in ("flood", "fire"):
        models[hazard] = tf.keras.models.load_model(build / f"lstm_{hazard}.keras")
        data = np.load(build / f"windows_{hazard}.npz")
        scalers[hazard] = (data["scaler_mean"], data["scaler_std"])

    def chance(hazard, day):
        end = index[day - timedelta(days=1)]
        prior = np.array([count(hazard, days[i - 1]) if i > 0 else 0 for i in range(end - WINDOW + 1, end + 1)])
        x = np.column_stack([weather[end - WINDOW + 1 : end + 1], prior])
        mean, std = scalers[hazard]
        return float(models[hazard].predict(((x - mean) / std)[np.newaxis, ...], verbose=0).ravel()[0])

    rows = []
    for hazard, name, day in events:
        if day is None:
            # The first day after the busiest ones with none in the next 72 hours.
            day = next(d for d in days[WINDOW + 1 : -3]
                       if d.month in (3, 4) and all(count(hazard, d + timedelta(k)) == 0 for k in range(3)))
        if day - timedelta(days=1) not in index or day + timedelta(days=2) not in index:
            continue
        recorded = sum(count(hazard, day + timedelta(k)) for k in range(3))
        window = range(index[day] - WINDOW, index[day])
        rows.append({
            "hazard": hazard,
            "event": name,
            "forecast_made": day.isoformat(),
            "chance_next_72h": round(chance(hazard, day), 3),
            "recorded_next_72h": recorded,
            "rain_last_14_days_mm": round(float(weather[list(window), 0].sum()), 1),
            "highest_signal_last_14_days": float(weather[list(window), 2].max()),
        })
    out = FORECAST / "heatmap" / f"backtest_{args.variant}.json"
    out.write_text(json.dumps({"variant": args.variant, "weather_from": args.weather_from or args.variant, "events": rows}, indent=2) + "\n", encoding="utf-8")
    print(f"{'hazard':<6} {'made':<11} {'chance':>7} {'recorded':>8} {'rain14':>7} {'signal':>6}  event")
    for r in rows:
        print(f"{r['hazard']:<6} {r['forecast_made']:<11} {r['chance_next_72h']:>7.3f} {r['recorded_next_72h']:>8} "
              f"{r['rain_last_14_days_mm']:>7} {r['highest_signal_last_14_days']:>6}  {r['event']}")


if __name__ == "__main__":
    main()
