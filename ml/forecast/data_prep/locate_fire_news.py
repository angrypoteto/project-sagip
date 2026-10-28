"""Turns the news reports gathered by collect_fire_news.py into incident
records for the forecast: keeps the fires in the City of Manila and gives
each one a position.

Where a report is placed, most exact first (the `precision` column):
  barangay  it names one of Manila's barangay numbers: that barangay's
            center (supabase/data/manila_barangays.csv)
  street    it names a street: OpenStreetMap's Nominatim finds it in that
            district (one request a second, answers kept on disk)
  district  only the district is known: the middle of the district
  city      only "Manila" is known: City Hall
The last two are good for "a fire happened that day" and too coarse for
the map of where fires happen: leave them out of the KDE.

Nothing is invented: a report that names no Manila district is left out
and counted. The date is the report's date, which is the day of the fire
or the day after.

Usage:
  python ml/forecast/data_prep/locate_fire_news.py

Reads ml/forecast/build/fire_news/, writes
ml/forecast/data/manila_fire_news.csv and prints the counts.
"""

import csv
import json
import re
import time
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
ROOT = FORECAST.parent.parent
NEWS = FORECAST / "build" / "fire_news"
CACHE = NEWS / "geocode.json"
OUT = FORECAST / "data" / "manila_fire_news.csv"
AGENT = "project-sagip capstone research (student project; one request a second)"

# How reports name the districts, and the district name in the barangay file.
DISTRICTS = {
    "Tondo": r"Tondo|Baseco|Parola|Isla Puting Bato|Smokey Mountain|Vitas",
    "Sampaloc": r"Sampaloc",
    "Santa Cruz": r"(?:Sta\.?|Santa) Cruz|Blumentritt|Tambunting",
    "Santa Mesa": r"(?:Sta\.?|Santa) Mesa|Nagtahan",
    "Santa Ana": r"(?:Sta\.?|Santa) Ana",
    "San Andres": r"San Andres",
    "San Nicolas": r"San Nicolas",
    "San Miguel": r"San Miguel",
    "Paco": r"Paco",
    "Pandacan": r"Pandacan",
    "Malate": r"Malate",
    "Ermita": r"Ermita",
    "Quiapo": r"Quiapo",
    "Binondo": r"Binondo|Divisoria",
    "Port Area": r"Port Area",
    "Intramuros": r"Intramuros",
}
ELSEWHERE = (
    r"Quezon City|Makati|Pasay|Caloocan|Mandaluyong|Taguig|Pasig|Para[nñ]aque|Las Pi[nñ]as"
    r"|Marikina|Valenzuela|Malabon|Navotas|Muntinlupa|San Juan City|Pateros|Cebu|Davao"
    r"|Cavite|Bulacan|Rizal province|Laguna|Antipolo|Cainta|Taytay"
)
STREET = re.compile(
    r"((?:[A-Z][\w.'-]*\.? ){1,4}(?:Street|St\.|Avenue|Ave\.|Boulevard|Blvd\.?|Road|Drive))"
)
MANILA_BOX = (14.53, 14.66, 120.93, 121.04)
CITY_HALL = (14.5995, 120.9842)


def load_barangays():
    by_name, by_district = {}, {}
    with (ROOT / "supabase" / "data" / "manila_barangays.csv").open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            point = (float(row["center_latitude"]), float(row["center_longitude"]))
            by_name[row["name"].lower()] = (row["district"], point)
            by_district.setdefault(row["district"], []).append(point)
    centers = {
        d: (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        for d, pts in by_district.items()
    }
    return by_name, centers


def geocode(query, cache):
    if query not in cache:
        url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(
            {"q": query, "format": "json", "limit": 1, "countrycodes": "ph"}
        )
        request = urllib.request.Request(url, headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            found = json.load(response)
        cache[query] = [float(found[0]["lat"]), float(found[0]["lon"])] if found else None
        CACHE.write_text(json.dumps(cache, indent=1), encoding="utf-8")
        time.sleep(1.1)
    return cache[query]


def in_manila(point):
    south, north, west, east = MANILA_BOX
    return point is not None and south <= point[0] <= north and west <= point[1] <= east


def record(entry, point, precision, place):
    return {
        "incident_id": f"AFN-{entry['id']}",
        "date": entry["date"],
        "hazard": "fire",
        "latitude": round(point[0], 5),
        "longitude": round(point[1], 5),
        "precision": precision,
        "place": place,
        "title": entry["title"],
        "source_url": entry["source_url"].split("?")[0],
        "archive_url": f"https://gcoe.tus-fire.com/asia_news/?p={entry['id']}",
    }


def main():
    by_name, centers = load_barangays()
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    rows, left_out = [], Counter()
    seen = set()

    for path in sorted(NEWS.glob("[0-9]*.json")):
        entry = json.loads(path.read_text(encoding="utf-8"))
        # The archive's own header and labels come before the report.
        text = entry["text"].split("Updated:", 1)[-1]
        head = entry["title"] + " " + text[:400]
        district = next(
            (d for d, pattern in DISTRICTS.items() if re.search(rf"\b(?:{pattern})\b", head)),
            None,
        )
        if district is None and not re.search(r"Manila(?! Bay)", entry["title"]):
            left_out["not said to be in the City of Manila"] += 1
            continue
        if re.search(ELSEWHERE, entry["title"]) or (
            re.search(ELSEWHERE, text[:200]) and "Manila" not in entry["title"]
        ):
            left_out["another city"] += 1
            continue
        if district is None:
            # "Fire in Manila" and no more: the day is known, the place is not.
            key = (entry["date"], entry["title"])
            if key not in seen:
                seen.add(key)
                rows.append(record(entry, CITY_HALL, "city", "Manila"))
            continue
        # Santa Mesa and San Andres are not districts of the barangay file
        # (their barangays are listed under Sampaloc, Santa Ana, and Malate).
        if district not in centers:
            found = geocode(f"{district}, Manila, Philippines", cache)
            if not in_manila(found):
                left_out["district not found"] += 1
                continue
            centers[district] = tuple(found)

        point, precision, place = None, None, district
        for number in re.findall(r"Barangay (\d+(?:-[A-Z])?)", text):
            known = by_name.get(f"barangay {number}".lower())
            # Other cities are already left out, and the numbers are
            # Manila's own, so the number alone places it.
            if known:
                point, precision, place = known[1], "barangay", f"Barangay {number}, {district}"
                break
        if point is None:
            for street in STREET.findall(text[:900]):
                street = street.strip()
                found = geocode(f"{street}, {district}, Manila, Philippines", cache)
                if in_manila(found):
                    point, precision, place = found, "street", f"{street}, {district}"
                    break
        if point is None:
            point, precision = centers[district], "district"

        key = (entry["date"], place)
        if key in seen:
            left_out["same day and place as another report"] += 1
            continue
        seen.add(key)
        rows.append(record(entry, point, precision, place))

    rows.sort(key=lambda r: (r["date"], r["incident_id"]))
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    print(f"{len(rows)} fires in Manila, {rows[0]['date']} to {rows[-1]['date']}")
    print("by year:", dict(sorted(Counter(r["date"][:4] for r in rows).items())))
    print("placed by:", dict(Counter(r["precision"] for r in rows)))
    print("by district:", dict(Counter(r["place"].split(", ")[-1] for r in rows).most_common()))
    print("left out:", dict(left_out))


if __name__ == "__main__":
    main()
