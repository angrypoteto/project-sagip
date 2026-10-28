"""Gives every DROMIC and TXTFIRE fire in Manila a position (Objective 2,
geocoding), most exact first (the `precision` column):

  barangay  the record names a barangay number: that barangay's centre
            (supabase/data/manila_barangays.csv); two or more barangays:
            the middle of their centres
  street    (TXTFIRE only) the alert names a street or a place: OpenStreetMap's
            Nominatim finds it (one request a second, answers kept in
            build/txtfire_geocode.json), and the point is kept only when it
            falls in a barangay of the district the alert names
  district  only the district is known, or the street was not found or fell
            outside its district: the middle of the district's barangays

District-only positions are good for "a fire happened that day" and too
coarse for the KDE (prepare_real.py leaves them out of it).

TXTFIRE alerts that never got past "For Verification", or were called a
false alarm, are not placed; prepare_real.py counts them as removed.

Usage (from the repo root, after collect_dromic.py and collect_txtfire.py):
  .venv/Scripts/python ml/forecast/data_prep/place_fires.py

Writes ml/forecast/data/manila_fire_dromic_placed.csv and
ml/forecast/data/manila_fire_txtfire_placed.csv.
"""

import csv
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
ROOT = FORECAST.parent.parent
sys.path.insert(0, str(FORECAST))  # the data_prep, lstm, kde, and heatmap folders import as packages

from shapely import STRtree  # noqa: E402
from shapely.geometry import Point, shape  # noqa: E402

from kde.kde import default_boundaries, load_boundaries  # noqa: E402

DATA = FORECAST / "data"
CACHE = FORECAST / "build" / "txtfire_geocode.json"
AGENT = "project-sagip capstone research (student project; one request a second)"
# How records name a district, and the districts of the barangay file it means.
DISTRICT_OF = {
    "Tondo": ["Tondo"], "Binondo": ["Binondo"], "Quiapo": ["Quiapo"], "San Nicolas": ["San Nicolas"],
    "Santa Cruz": ["Santa Cruz"], "Sampaloc": ["Sampaloc"], "San Miguel": ["San Miguel"], "Ermita": ["Ermita"],
    "Intramuros": ["Intramuros"], "Malate": ["Malate"], "Paco": ["Paco"], "Pandacan": ["Pandacan"],
    "Port Area": ["Port Area"], "Santa Ana": ["Santa Ana"], "San Andres": ["Santa Ana"],
    "Santa Mesa": ["Sampaloc"],
}
SPECIAL = {"baseco": "Barangay 649"}


def load_barangays():
    rows = {}
    with (ROOT / "supabase" / "data" / "manila_barangays.csv").open(encoding="utf-8") as f:
        for r in csv.DictReader(f):
            rows[r["name"]] = (r["district"], float(r["center_latitude"]), float(r["center_longitude"]))
    return rows


def district_centres(barangays):
    out = {}
    for name, cities in DISTRICT_OF.items():
        pts = [(lat, lng) for d, lat, lng in barangays.values() if d in cities]
        out[name] = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
    return out


class Locator:
    def __init__(self):
        raw = load_boundaries(default_boundaries())
        self.names = list(raw)
        self.shapes = [shape(raw[n]).buffer(0) for n in self.names]
        self.tree = STRtree(self.shapes)

    def barangay(self, lat, lng):
        p = Point(lng, lat)
        for i in self.tree.query(p):
            if self.shapes[i].contains(p):
                return self.names[i]
        return None


def geocode(query, cache):
    if query not in cache:
        url = "https://nominatim.openstreetmap.org/search?" + urllib.parse.urlencode(
            {"q": query, "format": "json", "limit": 1, "countrycodes": "ph"})
        req = urllib.request.Request(url, headers={"User-Agent": AGENT})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=60) as r:
                    found = json.load(r)
                break
            except Exception:  # noqa: BLE001
                if attempt == 2:
                    found = []
                time.sleep(5)
        cache[query] = [float(found[0]["lat"]), float(found[0]["lon"])] if found else None
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache, indent=1), encoding="utf-8")
        time.sleep(1.1)
    return cache[query]


def barangay_names(numbers, barangays):
    names = []
    for n in numbers:
        n = n.upper().replace(" ", "")
        if not re.search(r"-[A-C]$", n) and re.search(r"[A-C]$", n):
            n = n[:-1] + "-" + n[-1]
        if f"Barangay {n}" in barangays:
            names.append(f"Barangay {n}")
    return names


def placed(row, lat, lng, precision, barangay, how):
    return {**row, "latitude": f"{lat:.5f}", "longitude": f"{lng:.5f}", "precision": precision,
            "barangay": barangay, "placed_by": how}


def place_dromic(barangays, centres):
    rows = list(csv.DictReader((DATA / "manila_fire_dromic.csv").open(encoding="utf-8")))
    out = []
    for r in rows:
        names = barangay_names([b for b in r["barangays"].split(";") if b], barangays)
        if not names and "baseco" in r["title"].lower():
            names = [SPECIAL["baseco"]]
        if names:
            lat = sum(barangays[n][1] for n in names) / len(names)
            lng = sum(barangays[n][2] for n in names) / len(names)
            out.append(placed(r, lat, lng, "barangay", names[0], "barangay centre"))
        elif r["district"] in centres:
            lat, lng = centres[r["district"]]
            out.append(placed(r, lat, lng, "district", "", "district centre"))
        else:
            out.append(placed(r, 14.5995, 120.9842, "city", "", "City Hall (no place given)"))
    return out


def street_query(place, district):
    text = re.sub(r"(?i)\b(city of manila|manila city|manila|metro|ncr|brgy\.?\s*\d+\S*|barangay\s*\d+\S*|"
                  r"zone\s*\d+|district\s*\d+)\b", " ", place)
    text = re.sub(r"(?i)\b" + re.escape(district) + r"\b", " ", text) if district else text
    text = " ".join(text.replace(",", " ").split())
    return f"{text}, {district}, Manila" if text else None


def place_txtfire(barangays, centres, locator):
    rows = list(csv.DictReader((DATA / "manila_fire_txtfire.csv").open(encoding="utf-8")))
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    names_district = {n: d for n, (d, _, _) in barangays.items()}
    out = []
    for r in rows:
        if r["kind"] not in ("alarm", "fire, no alarm raised"):
            continue
        district = r["district"]
        names = barangay_names([r["barangay"]], barangays) if r["barangay"] else []
        if not names and "baseco" in r["place"].lower():
            names = [SPECIAL["baseco"]]
        if names:
            _, lat, lng = barangays[names[0]]
            out.append(placed(r, lat, lng, "barangay", names[0], "barangay centre"))
            continue
        query = street_query(r["place"], district) if district else None
        point = geocode(query, cache) if query else None
        if point:
            found = locator.barangay(point[0], point[1])
            if found and names_district.get(found) in DISTRICT_OF.get(district, []):
                out.append(placed(r, point[0], point[1], "street", found, "OpenStreetMap, inside its district"))
                continue
        if district in centres:
            lat, lng = centres[district]
            how = "district centre (street not found)" if query and not point else (
                "district centre (street found outside the district)" if point else "district centre")
            out.append(placed(r, lat, lng, "district", "", how))
        else:
            out.append(placed(r, 14.5995, 120.9842, "city", "", "City Hall (no district)"))
    return out


def write(path, rows):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main():
    barangays = load_barangays()
    centres = district_centres(barangays)
    locator = Locator()
    dromic = place_dromic(barangays, centres)
    write(DATA / "manila_fire_dromic_placed.csv", dromic)
    txt = place_txtfire(barangays, centres, locator)
    write(DATA / "manila_fire_txtfire_placed.csv", txt)
    for name, rows in (("DROMIC", dromic), ("TXTFIRE", txt)):
        counts = {}
        for r in rows:
            counts[r["placed_by"]] = counts.get(r["placed_by"], 0) + 1
        print(name, len(rows), counts)


if __name__ == "__main__":
    main()
