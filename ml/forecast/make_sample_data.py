"""Writes SAMPLE inputs for the 72-hour forecast (FR4, plan 10.5):

  ml/forecast/data/sample_weather_daily.csv   one row per day
  ml/forecast/data/sample_incidents.csv       one row per incident

THIS IS NOT PAGASA OR MDRRMD DATA. Every number is made up by the rules
below, so the data preparation and the KDE can be built and tested before
the real records arrive (thesis Table 3.1). Nothing measured on it is a
result. Replace both files with the real ones (same columns) and rerun
prepare_windows.py and kde.py.

The rules, roughly: a wet season from June to November; a few typhoons a
year that bring a wind signal, heavy rain, and sometimes a storm surge;
floods follow heavy rain; fires are more common in the dry months and do
not depend on rain; storm surge incidents happen only on surge days.
Incidents fall around a handful of made-up hotspots. A few bad rows are
added on purpose (duplicates, a point outside Manila, an unknown hazard, a
date outside the period) so the cleaning step has something to remove.

Usage: python ml/forecast/make_sample_data.py
"""

import csv
import math
from datetime import date, timedelta
from pathlib import Path

import numpy as np

SEED = 20261002
START = date(2023, 1, 1)
END = date(2025, 12, 31)
DATA = Path(__file__).parent / "data"
EARTH_RADIUS_M = 6_371_008.8

# (latitude, longitude, spread in metres, share of that hazard's incidents)
HOTSPOTS = {
    "flood": [
        (14.6091, 120.9925, 250, 0.30),  # España and Dapitan, Sampaloc
        (14.6197, 120.9671, 300, 0.25),  # Juan Luna, Tondo
        (14.5825, 120.9845, 280, 0.20),  # Taft and UN Avenue
        (14.6010, 121.0120, 300, 0.15),  # Santa Mesa
        (14.5790, 120.9990, 250, 0.10),  # Paco
    ],
    "fire": [
        (14.6170, 120.9650, 350, 0.35),  # Tondo
        (14.5990, 120.9840, 200, 0.20),  # Quiapo
        (14.6110, 121.0000, 300, 0.20),  # Sampaloc
        (14.5900, 120.9590, 200, 0.15),  # Baseco
        (14.5920, 121.0080, 300, 0.10),  # Pandacan
    ],
    "storm_surge": [
        (14.5880, 120.9620, 200, 0.45),  # Baseco and Port Area
        (14.5720, 120.9810, 180, 0.35),  # Roxas Boulevard, Malate
        (14.6230, 120.9590, 220, 0.20),  # Tondo shore
    ],
}


def days():
    d = START
    while d <= END:
        yield d
        d += timedelta(days=1)


def make_weather(rng):
    """One made-up record per day: rain, wind signal, wind, storm surge."""
    rows = []
    all_days = list(days())
    signal = {d: 0 for d in all_days}
    surge = {d: 0.0 for d in all_days}
    extra_rain = {d: 0.0 for d in all_days}
    wind = {d: float(rng.uniform(8, 30)) for d in all_days}

    for year in range(START.year, END.year + 1):
        for _ in range(int(rng.integers(5, 8))):
            first = date(year, 7, 1) + timedelta(days=int(rng.integers(0, 140)))
            peak = int(rng.choice([1, 2, 3, 4], p=[0.35, 0.35, 0.2, 0.1]))
            length = int(rng.integers(2, 5))
            for i in range(length):
                d = first + timedelta(days=i)
                if d not in signal:
                    continue
                # Strongest in the middle of its stay.
                level = max(1, peak - abs(i - length // 2))
                signal[d] = max(signal[d], level)
                wind[d] = max(wind[d], float(rng.uniform(45, 70) + 25 * level))
                extra_rain[d] += float(rng.gamma(2.0, 25.0 * level))
                if level >= 2:
                    surge[d] = max(surge[d], round(float(rng.uniform(0.4, 0.9) * level), 1))

    for d in all_days:
        wet = 6 <= d.month <= 11
        rains = rng.random() < (0.62 if wet else 0.12)
        total = float(rng.gamma(1.3, 16.0 if wet else 6.0)) if rains else 0.0
        total += extra_rain[d]
        hourly = total * float(rng.uniform(0.15, 0.5))
        rows.append({
            "date": d.isoformat(),
            "rainfall_total_mm": round(total, 1),
            "rainfall_max_hourly_mm": round(min(hourly, 120.0), 1),
            "typhoon_signal": signal[d],
            "max_wind_kph": round(wind[d], 1),
            "storm_surge_m": surge[d],
        })
    return rows


def place(rng, hazard):
    """A point near one of the hazard's made-up hotspots."""
    spots = HOTSPOTS[hazard]
    lat0, lng0, spread, _ = spots[int(rng.choice(len(spots), p=[s[3] for s in spots]))]
    north = float(rng.normal(0, spread))
    east = float(rng.normal(0, spread))
    lat = lat0 + math.degrees(north / EARTH_RADIUS_M)
    lng = lng0 + math.degrees(east / (EARTH_RADIUS_M * math.cos(math.radians(lat0))))
    return round(lat, 6), round(lng, 6)


def make_incidents(rng, weather):
    rows = []
    rain = [w["rainfall_total_mm"] for w in weather]
    for i, w in enumerate(weather):
        d = date.fromisoformat(w["date"])
        yesterday = rain[i - 1] if i > 0 else 0.0
        flood_rate = (
            0.01
            + 0.10 * max(0.0, w["rainfall_total_mm"] - 30) / 10
            + 0.05 * max(0.0, yesterday - 30) / 10
            + (0.8 if w["typhoon_signal"] >= 2 else 0.0)
        )
        fire_rate = 0.22 * (1.8 if 3 <= d.month <= 5 else 1.4 if d.month == 12 else 1.0)
        if w["rainfall_total_mm"] > 20:
            fire_rate *= 0.5
        surge_rate = 0.9 * w["storm_surge_m"] if w["storm_surge_m"] >= 1.0 else 0.0
        for hazard, rate in (("flood", flood_rate), ("fire", fire_rate), ("storm_surge", surge_rate)):
            for _ in range(int(rng.poisson(min(rate, 12.0)))):
                lat, lng = place(rng, hazard)
                rows.append({"date": d.isoformat(), "hazard": hazard, "latitude": lat, "longitude": lng})

    # Bad rows on purpose, for the cleaning step.
    rows += [dict(r) for r in rows[10:16]]  # six exact duplicates
    rows.append({"date": "2024-08-03", "hazard": "flood", "latitude": 14.4005, "longitude": 121.2001})
    rows.append({"date": "2024-08-04", "hazard": "fire", "latitude": 15.1200, "longitude": 120.5900})
    rows.append({"date": "2024-08-05", "hazard": "landslide", "latitude": 14.6000, "longitude": 120.9900})
    rows.append({"date": "2022-12-30", "hazard": "flood", "latitude": 14.6000, "longitude": 120.9900})
    rows.append({"date": "not a date", "hazard": "fire", "latitude": 14.6000, "longitude": 120.9900})

    order = rng.permutation(len(rows))
    rows = [rows[int(i)] for i in order]
    rows.sort(key=lambda r: r["date"])
    for n, r in enumerate(rows, start=1):
        r["incident_id"] = f"S-{n:05d}"
    return rows


def write(path, rows, columns):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main():
    rng = np.random.default_rng(SEED)
    weather = make_weather(rng)
    incidents = make_incidents(rng, weather)
    write(
        DATA / "sample_weather_daily.csv",
        weather,
        ["date", "rainfall_total_mm", "rainfall_max_hourly_mm", "typhoon_signal", "max_wind_kph", "storm_surge_m"],
    )
    write(
        DATA / "sample_incidents.csv",
        incidents,
        ["incident_id", "date", "hazard", "latitude", "longitude"],
    )
    by = {}
    for r in incidents:
        by[r["hazard"]] = by.get(r["hazard"], 0) + 1
    print(f"{len(weather)} days of made-up weather, {len(incidents)} made-up incidents: {by}")


if __name__ == "__main__":
    main()
