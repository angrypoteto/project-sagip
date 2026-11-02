"""EXPERIMENT (Joshua, 2026-11-02: "try the extra-inputs experiment"): the
daily lowest relative humidity over the City of Manila, for the fire inputs
that are not in the thesis feature set (prepare_real.py --fire-extras).

Source: Open-Meteo's historical archive (ERA5), the same point and source as
the rainfall of the recorded variant; run-forecast could read the same value
live from Open-Meteo's forecast API. Free, no sign-up.

Usage (from ml/forecast):
  ../../.venv/Scripts/python data_prep/fetch_fire_inputs.py

Writes data/manila_humidity_daily.csv (date, humidity_min_pct).
"""

import csv
import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
FORECAST = HERE.parent
OUT = FORECAST / "data" / "manila_humidity_daily.csv"
ARCHIVE = "https://archive-api.open-meteo.com/v1/archive"
# Manila City Hall, as fetch_weather.py.
LAT, LNG = 14.5995, 120.9842


def main(start="2021-01-01", end="2026-10-05"):
    url = ARCHIVE + "?" + urllib.parse.urlencode({
        "latitude": LAT, "longitude": LNG, "start_date": start, "end_date": end,
        "daily": "relative_humidity_2m_min", "timezone": "Asia/Manila",
    })
    with urllib.request.urlopen(url, timeout=120) as r:
        daily = json.load(r)["daily"]
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f, lineterminator="\n")
        w.writerow(["date", "humidity_min_pct"])
        for day, value in zip(daily["time"], daily["relative_humidity_2m_min"]):
            w.writerow([day, "" if value is None else value])
    print(f"wrote {OUT} ({len(daily['time'])} days)")


if __name__ == "__main__":
    main(*sys.argv[1:])
