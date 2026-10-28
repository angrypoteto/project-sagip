"""An estimate of the PAGASA wind signal over Manila for every day since
2012, from tropical cyclone tracks (Objective 2: the "highest typhoon
signal" feature).

The thesis feature is the highest Tropical Cyclone Wind Signal (TCWS) PAGASA
raised over Manila each day. PAGASA's own record of signals has not been
obtained; news reports gave only 23 days (data/manila_signals.csv). This
estimates the rest from NOAA's IBTrACS best tracks (public domain; Western
Pacific, every 3 hours, downloaded to data/downloads/ibtracs/):

  1. each track point: the storm's highest 10-minute wind (JMA's, else
     WMO's, else 0.88 x the US 1-minute wind) and its distance to Manila
     City Hall
  2. the wind it gives Manila: the full wind within the radius of maximum
     wind (the US estimate, else 40 km), then falling off as
     (radius / distance) ** 0.6 (a modified Rankine vortex)
  3. the day's highest such wind, by Manila date (UTC + 8 hours)
  4. PAGASA raises a signal for winds expected within 36 hours, so a day's
     signal takes the higher of that day's wind and the next day's
  5. PAGASA's TCWS bands for that wind: signal 1 from 39 km/h, 2 from 62,
     3 from 89, 4 from 118, 5 from 185

It is a stand-in, and step 4 reads the next day's track as PAGASA's
forecast would have foreseen it. The script prints how it compares with the
23 news-reported days.

Usage (from the repo root):
  .venv/Scripts/python ml/forecast/data_prep/storm_signal.py

Writes ml/forecast/data/manila_storm_signal.csv: every day a storm gave
Manila an estimated 39 km/h or more, or came within 500 km.
"""

import csv
import math
from datetime import datetime, timedelta
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
TRACKS = FORECAST / "data" / "downloads" / "ibtracs" / "ibtracs_wp_2011_near_ph.csv"
OUT = FORECAST / "data" / "manila_storm_signal.csv"
MANILA = (14.5995, 120.9842)
DEFAULT_RMW_KM = 40
DECAY = 0.6  # chosen from 0.4, 0.5, 0.6 against the 23 news days: 19 hit, about 7 signal days a year
BANDS = ((185, 5), (118, 4), (89, 3), (62, 2), (39, 1))


def km(a, b):
    p1, p2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    h = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def number(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def signal_for(kph):
    for low, level in BANDS:
        if kph >= low:
            return level
    return 0


def main():
    days = {}
    with TRACKS.open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["TRACK_TYPE"] != "main":
                continue
            knots = number(r["TOKYO_WIND"]) or number(r["WMO_WIND"])
            if knots is None and number(r["USA_WIND"]) is not None:
                knots = 0.88 * number(r["USA_WIND"])
            if not knots:
                continue
            distance = km(MANILA, (float(r["LAT"]), float(r["LON"])))
            rmw = number(r["USA_RMW"])
            radius = rmw * 1.852 if rmw else DEFAULT_RMW_KM
            vmax = knots * 1.852
            wind = vmax if distance <= radius else vmax * (radius / distance) ** DECAY
            day = (datetime.fromisoformat(r["ISO_TIME"]) + timedelta(hours=8)).date().isoformat()
            best = days.get(day)
            if best is None or wind > best["wind"]:
                days[day] = {"wind": wind, "storm": r["NAME"], "distance": distance, "vmax": vmax}
            elif distance < best["distance"]:
                best["distance"] = distance
    rows = []
    for day in sorted(days):
        d = days[day]
        following = days.get((datetime.fromisoformat(day) + timedelta(1)).date().isoformat())
        ahead = max(d["wind"], following["wind"] if following else 0.0)
        if ahead >= 39 or d["distance"] <= 500:
            rows.append({
                "date": day, "storm": d["storm"].title(), "nearest_km": round(d["distance"]),
                "storm_max_wind_kph": round(d["vmax"]), "est_wind_at_manila_kph": round(d["wind"]),
                "est_wind_next_36h_kph": round(ahead), "signal_estimate": signal_for(ahead),
            })
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    est = {r["date"]: r["signal_estimate"] for r in rows}
    news = list(csv.DictReader((FORECAST / "data" / "manila_signals.csv").open(encoding="utf-8")))
    hit = sum(1 for r in news if est.get(r["date"], 0) >= 1)
    near = sum(1 for r in news if any(
        est.get((datetime.fromisoformat(r["date"]) + timedelta(k)).date().isoformat(), 0) >= 1 for k in (-1, 0, 1)))
    print(f"{len(rows)} days kept, {sum(1 for r in rows if r['signal_estimate'] >= 1)} with an estimated signal")
    print(f"news-reported signal days: {len(news)}; estimate >= 1 on the same day {hit}, within a day {near}")
    for r in news:
        print(f"  {r['date']} news {r['typhoon_signal']}  estimate {est.get(r['date'], 0)}  ({r['storm']})")


if __name__ == "__main__":
    main()
