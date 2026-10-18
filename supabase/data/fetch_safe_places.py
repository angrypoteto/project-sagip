"""Downloads and checks the places in Manila that can serve as a safe place.

Safe places (Joshua, 2026-10-19): the nearest place that suits the
emergency. Schools, barangay halls, and covered courts for a flood; open
ground (basketball courts, parks, plazas) away from a fire or a collapse;
a hospital for a medical emergency. The rules are in
`packages/shared/lib/src/models/safe_place.dart` and in the migration
`safe_places`; this script only gathers the places.

Source (public, read with the date in SOURCE): OpenStreetMap through the
Overpass API. Data (c) OpenStreetMap contributors, ODbL. The MDRRMD's own
list of evacuation centers is not public: an admin adds those on the
dashboard (A2, Safe places), and they are kept apart from these rows.

Every place must lie inside one of Manila's 897 barangays (the PSA
boundaries in `manila_barangays.json`); it is tagged with that barangay.
The same school or park mapped twice (a point and an outline with the same
name within 150 m) is kept once.

Writes:
  supabase/data/manila_safe_places.sql   inserts for the hosted project
                                         (safe to run again; an admin's
                                         changes to a row are kept)
  packages/shared/lib/src/data/manila_safe_places_data.dart
                                         the same list bundled in the app,
                                         so it works offline

Run from the repo root with any Python 3.10+ (standard library only):
  python supabase/data/fetch_safe_places.py
  dart format packages/shared/lib/src/data
"""

from __future__ import annotations

import datetime
import json
import math
import os
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "supabase", "data")
DART = os.path.join(ROOT, "packages", "shared", "lib", "src", "data", "manila_safe_places_data.dart")

SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.private.coffee/api/interpreter",
]
BOX = "(14.54,120.94,14.65,121.03)"  # Manila and a margin; clipped below.
QUERY = f"""[out:json][timeout:120];
(
  nwr["amenity"~"^(school|college|university)$"]{BOX};
  nwr["amenity"="townhall"]{BOX};
  nwr["leisure"="sports_centre"]{BOX};
  nwr["leisure"="pitch"]["sport"~"basketball"]{BOX};
  nwr["leisure"="park"]{BOX};
  nwr["place"="square"]{BOX};
  nwr["emergency"="assembly_point"]{BOX};
  nwr["amenity"="hospital"]{BOX};
);
out tags center;"""

TODAY = datetime.date.today().isoformat()
SOURCE = f"OpenStreetMap, {TODAY}"


def kind_of(tags: dict) -> str | None:
    """The safe place kind of an OpenStreetMap feature (see SafePlaceKind)."""
    amenity, leisure = tags.get("amenity"), tags.get("leisure")
    if amenity in ("school", "college", "university"):
        return "school"
    if amenity == "townhall":
        return "barangayHall"
    if amenity == "hospital":
        return "hospital"
    if leisure == "sports_centre":
        return "coveredCourt"
    if leisure == "pitch":
        return "coveredCourt" if tags.get("covered") == "yes" else "basketballCourt"
    if leisure == "park" or tags.get("place") == "square" or tags.get("emergency") == "assembly_point":
        return "openSpace"
    return None


# ------------------------------------------------------------ boundaries

def decode(encoded: str) -> list[tuple[float, float]]:
    """Encoded Polyline Algorithm, precision 1e-5, (lat, lng)."""
    points, index, lat, lng = [], 0, 0, 0
    while index < len(encoded):
        for axis in (0, 1):
            shift = result = 0
            while True:
                b = ord(encoded[index]) - 63
                index += 1
                result |= (b & 0x1F) << shift
                shift += 5
                if b < 0x20:
                    break
            delta = ~(result >> 1) if result & 1 else result >> 1
            if axis == 0:
                lat += delta
            else:
                lng += delta
        points.append((lat / 1e5, lng / 1e5))
    return points


def in_ring(lat: float, lng: float, ring) -> bool:
    hit = False
    j = len(ring) - 1
    for i in range(len(ring)):
        (ai, bi), (aj, bj) = ring[i], ring[j]
        if (ai > lat) != (aj > lat) and lng < (bj - bi) * (lat - ai) / (aj - ai) + bi:
            hit = not hit
        j = i
    return hit


def load_barangays():
    with open(os.path.join(DATA, "manila_barangays.json"), encoding="utf-8") as f:
        data = json.load(f)
    shapes = []
    for b in data["barangays"]:
        rings = [decode(r) for polygon in b["polygons"] for r in polygon]
        lats = [p[0] for r in rings for p in r]
        lngs = [p[1] for r in rings for p in r]
        shapes.append((b["name"], b["district"], rings, (min(lats), max(lats), min(lngs), max(lngs))))
    return shapes


def barangay_at(shapes, lat, lng):
    for name, district, rings, (a, b, c, d) in shapes:
        if a <= lat <= b and c <= lng <= d and any(in_ring(lat, lng, r) for r in rings):
            return name, district
    return None


# ------------------------------------------------------------ download

def fetch() -> list[dict]:
    body = urllib.parse.urlencode({"data": QUERY}).encode()
    last = None
    for url in SERVERS:
        try:
            req = urllib.request.Request(url, data=body, headers={
                "User-Agent": "sagip-capstone/1.0 (student project; safe places)",
                "Accept": "application/json",
            })
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)["elements"]
        except Exception as e:  # busy server: try the next one
            last = e
            print(f"{url}: {e}", file=sys.stderr)
    raise SystemExit(f"Overpass did not answer: {last}")


def meters(a, b) -> float:
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371008.8 * math.asin(math.sqrt(h))


def clean_name(tags: dict) -> str | None:
    name = (tags.get("name") or tags.get("name:en") or "").strip()
    return " ".join(name.split())[:120] or None


def main() -> None:
    shapes = load_barangays()
    elements = fetch()
    places, outside, skipped = [], 0, 0
    for e in elements:
        tags = e.get("tags", {})
        kind = kind_of(tags)
        if kind is None:
            skipped += 1
            continue
        if tags.get("access") in ("private", "no"):
            skipped += 1
            continue
        lat = e.get("lat", e.get("center", {}).get("lat"))
        lng = e.get("lon", e.get("center", {}).get("lon"))
        if lat is None or lng is None:
            skipped += 1
            continue
        where = barangay_at(shapes, lat, lng)
        if where is None:
            outside += 1
            continue
        places.append({
            "id": f"osm-{e['type'][0]}{e['id']}",
            "name": clean_name(tags),
            "kind": kind,
            "lat": round(lat, 6),
            "lng": round(lng, 6),
            "barangay": where[0],
            "district": where[1],
            "outline": e["type"] != "node",
        })

    # The same named place mapped twice: keep the outline (its center).
    places.sort(key=lambda p: (not p["outline"], p["id"]))
    kept: list[dict] = []
    duplicates = 0
    for p in places:
        if p["name"] and any(
            k["name"] == p["name"] and k["kind"] == p["kind"]
            and meters((k["lat"], k["lng"]), (p["lat"], p["lng"])) < 150
            for k in kept
        ):
            duplicates += 1
            continue
        kept.append(p)
    kept.sort(key=lambda p: (p["kind"], p["district"], p["barangay"], p["name"] or "", p["id"]))

    counts: dict[str, int] = {}
    for p in kept:
        counts[p["kind"]] = counts.get(p["kind"], 0) + 1
    print(f"{len(elements)} read, {len(kept)} kept, {outside} outside Manila, "
          f"{duplicates} mapped twice, {skipped} skipped")
    print(", ".join(f"{k} {v}" for k, v in sorted(counts.items())))

    write_sql(kept)
    write_dart(kept)


def sql_text(v: str | None) -> str:
    return "null" if v is None else "'" + v.replace("'", "''") + "'"


def write_sql(places: list[dict]) -> None:
    rows = ",\n".join(
        f"  ({sql_text(p['id'])}, {sql_text(p['name'])}, '{p['kind']}', {p['lat']}, {p['lng']}, "
        f"{sql_text(p['barangay'])}, {sql_text(p['district'])}, '{SOURCE}')"
        for p in places
    )
    text = f"""-- GENERATED by supabase/data/fetch_safe_places.py. Do not edit by hand.
-- {len(places)} places in Manila that can serve as a safe place, from
-- OpenStreetMap (data (c) OpenStreetMap contributors, ODbL), read {TODAY}.
-- Run in the SQL editor after the migration `safe_places`. Safe to run
-- again: the map's own fields are refreshed, and whatever an admin changed
-- (hidden, renamed, marked official) is kept.

insert into public.safe_place
  (place_id, name, kind, latitude, longitude, barangay, district, source)
values
{rows}
on conflict (place_id) do update
   set latitude = excluded.latitude,
       longitude = excluded.longitude,
       barangay = excluded.barangay,
       district = excluded.district,
       source = excluded.source
 where public.safe_place.updated_by is null;
"""
    with open(os.path.join(DATA, "manila_safe_places.sql"), "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def dart_text(v: str | None) -> str:
    if v is None:
        return "null"
    return "'" + v.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def write_dart(places: list[dict]) -> None:
    rows = "\n".join(
        f"  SafePlace(id: {dart_text(p['id'])}, name: {dart_text(p['name'])}, "
        f"kind: SafePlaceKind.{p['kind']}, location: GeoPoint({p['lat']}, {p['lng']}), "
        f"barangay: {dart_text(p['barangay'])}, district: {dart_text(p['district'])}),"
        for p in places
    )
    text = f"""// GENERATED by supabase/data/fetch_safe_places.py. Do not edit by hand.
// Source: {SOURCE} (data (c) OpenStreetMap contributors, ODbL).

part of 'manila_safe_places.dart';

/// {len(places)} places in Manila that can serve as a safe place, bundled so
/// the nearest ones can be found offline. The server's list (with an
/// admin's changes and MDRRMD's evacuation centers) is used when online.
const manilaSafePlaces = <SafePlace>[
{rows}
];
"""
    with open(DART, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


if __name__ == "__main__":
    main()
