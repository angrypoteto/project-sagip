"""Real past daily weather for the City of Manila, for training the LSTM
(FR4, plan 10.5): one record per day in the format prepare_windows.py
reads.

Source: Open-Meteo's historical weather archive (ERA5 reanalysis, about
a 9 to 25 km grid; https://open-meteo.com, CC BY 4.0), at the city's
center. It gives three of the five weather features:
  - rainfall_total_mm       the day's precipitation
  - rainfall_max_hourly_mm  the wettest hour of the day
  - max_wind_kph            the day's highest 10 m wind speed

It does NOT give the other two, and nothing here makes them up:
  - typhoon_signal  the highest PAGASA wind signal over Manila that day
  - storm_surge_m   the storm surge height PAGASA warned of
Those come from PAGASA's records. Pass them with --signals as a CSV of
only the days that had one (date,typhoon_signal,storm_surge_m); every day
not listed is then written as 0. Without --signals the two columns are
left empty and prepare_windows.py refuses the file, which is the point.

A reanalysis is a model's reconstruction, not a rain gauge: it smooths
short, local downpours. If PAGASA's own daily records for Port Area or
Science Garden are obtained, use those instead (same columns).

Usage:
  python ml/forecast/data_prep/fetch_weather.py --start 2021-01-01 --end 2026-10-10
  python ml/forecast/data_prep/fetch_weather.py --start ... --end ... --signals ml/forecast/data/manila_signals.csv

Writes ml/forecast/data/manila_weather_daily.csv.
"""

import argparse
import csv
import json
import time
import urllib.parse
import urllib.request
from datetime import date
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
# Manila City Hall, about the middle of the city.
LATITUDE, LONGITUDE = 14.5995, 120.9842
COLUMNS = (
    "date",
    "rainfall_total_mm",
    "rainfall_max_hourly_mm",
    "typhoon_signal",
    "max_wind_kph",
    "storm_surge_m",
)


def fetch_year(start, end):
    query = urllib.parse.urlencode(
        {
            "latitude": LATITUDE,
            "longitude": LONGITUDE,
            "start_date": start.isoformat(),
            "end_date": end.isoformat(),
            "daily": "precipitation_sum,wind_speed_10m_max",
            "hourly": "precipitation",
            "wind_speed_unit": "kmh",
            "timezone": "Asia/Manila",
        }
    )
    request = urllib.request.Request(
        f"{ARCHIVE}?{query}", headers={"User-Agent": "project-sagip (capstone)"}
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def daily_records(payload):
    """One record per day; the wettest hour comes from the hourly series."""
    wettest = {}
    for stamp, mm in zip(payload["hourly"]["time"], payload["hourly"]["precipitation"]):
        if mm is not None:
            day = stamp[:10]
            wettest[day] = max(wettest.get(day, 0.0), mm)
    daily = payload["daily"]
    for day, total, wind in zip(
        daily["time"], daily["precipitation_sum"], daily["wind_speed_10m_max"]
    ):
        if total is None or wind is None or day not in wettest:
            raise SystemExit(f"{day}: the archive has no complete record yet")
        yield day, round(total, 1), round(wettest[day], 1), round(wind, 1)


def read_signals(path):
    signals = {}
    with Path(path).open(newline="", encoding="utf-8-sig") as f:
        for row in csv.DictReader(f):
            signal = int(row["typhoon_signal"] or 0)
            surge = float(row["storm_surge_m"] or 0)
            if not 0 <= signal <= 5 or not 0 <= surge <= 10:
                raise SystemExit(f"{row['date']}: signal or surge out of range")
            signals[date.fromisoformat(row["date"]).isoformat()] = (signal, surge)
    return signals


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--start", required=True, type=date.fromisoformat)
    parser.add_argument("--end", required=True, type=date.fromisoformat)
    parser.add_argument("--signals", help="CSV: date,typhoon_signal,storm_surge_m")
    parser.add_argument("--out", default=FORECAST / "data" / "manila_weather_daily.csv")
    args = parser.parse_args()
    if args.end < args.start:
        raise SystemExit("--end is before --start")
    signals = read_signals(args.signals) if args.signals else None

    rows = []
    for year in range(args.start.year, args.end.year + 1):
        start = max(args.start, date(year, 1, 1))
        end = min(args.end, date(year, 12, 31))
        rows.extend(daily_records(fetch_year(start, end)))
        time.sleep(1)  # the archive is free: go easy on it

    expected = (args.end - args.start).days + 1
    if len(rows) != expected or len({r[0] for r in rows}) != expected:
        raise SystemExit(f"expected {expected} days, got {len(rows)}")

    with Path(args.out).open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(COLUMNS)
        for day, total, hourly, wind in rows:
            signal, surge = signals.get(day, (0, 0.0)) if signals is not None else ("", "")
            writer.writerow([day, total, hourly, signal, wind, surge])

    wet = sum(1 for r in rows if r[1] >= 1)
    print(f"{len(rows)} days, {rows[0][0]} to {rows[-1][0]}; {wet} with 1 mm or more")
    print(f"wettest day: {max(rows, key=lambda r: r[1])}")
    if signals is None:
        print("typhoon_signal and storm_surge_m are EMPTY: give --signals to fill them")
    else:
        print(f"{len(signals)} days with a signal or a surge; the rest written as 0")


if __name__ == "__main__":
    main()
