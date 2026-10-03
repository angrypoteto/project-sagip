"""Downloads, checks, and converts the boundaries of Manila's 897 barangays.

Sources (both public, read 2026-10-03):

- Boundaries: the Philippine Statistics Authority's barangay layer, served
  by GeoRiskPH (https://portal.georisk.gov.ph/arcgis/rest/services/PSA/
  Barangay/MapServer/4). PSA calls them "indicative boundaries", made for
  the 2015 census. Attribution: Philippine Statistics Authority (PSA).
- The official list: the Philippine Standard Geographic Code (PSGC) as
  published by PSA, read through https://psgc.gitlab.io/api. Every barangay
  name and 10-digit code in the layer must match it, or the script stops.

The layer has 899 shapes: the 897 barangays, plus Tutuban Mall (claimed by
five Tondo barangays) and Manila North Cemetery, which belong to no
barangay. Those two count as Manila (for the "inside Manila" check) but are
not barangays.

Writes:
  supabase/data/manila_barangays.json   compact file the database loads
                                        (private.load_barangays)
  supabase/data/manila_barangays.csv    name, district, code, center, area
  packages/shared/lib/src/data/manila_barangays_data.dart
                                        the same list bundled in the apps

Run from the repo root with any Python 3.10+ (standard library only):
  python supabase/data/fetch_barangays.py
  dart format packages/shared/lib/src/data
"""

from __future__ import annotations

import csv
import io
import json
import math
import os
import re
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DATA = os.path.join(ROOT, "supabase", "data")
DART = os.path.join(ROOT, "packages", "shared", "lib", "src", "data", "manila_barangays_data.dart")

LAYER = "https://portal.georisk.gov.ph/arcgis/rest/services/PSA/Barangay/MapServer/4/query"
PSGC = "https://psgc.gitlab.io/api/cities/133900000/barangays/"
MANILA_CITY_CODE = "133900000"
SOURCE = (
    "Philippine Statistics Authority (PSA) barangay boundaries via GeoRiskPH, "
    "indicative, 2015 census layer; names and codes checked against the PSGC"
)

# PSA's sub-municipality names, as the apps write the district.
DISTRICTS = {"Tondo I / II": "Tondo"}


def get(url: str, params: dict[str, str] | None = None) -> bytes:
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": "SAGIP-capstone-data/1.0"})
    with urllib.request.urlopen(req, timeout=180) as r:
        return r.read()


# ------------------------------------------------------------ geometry

def rings_of(geometry: dict) -> list[list[list[tuple[float, float]]]]:
    """Polygons as lists of rings of (lng, lat), each ring left open."""
    if geometry["type"] == "Polygon":
        polys = [geometry["coordinates"]]
    elif geometry["type"] == "MultiPolygon":
        polys = geometry["coordinates"]
    else:
        raise ValueError(geometry["type"])
    out = []
    for poly in polys:
        rings = []
        for ring in poly:
            pts = [(round(x, 5), round(y, 5)) for x, y in ring]
            if pts[0] == pts[-1]:
                pts = pts[:-1]
            # Drop points that repeat after rounding, including a last point
            # that came back to the first (map painters divide by zero on it).
            clean = [p for i, p in enumerate(pts) if i == 0 or p != pts[i - 1]]
            while len(clean) > 1 and clean[-1] == clean[0]:
                clean.pop()
            if len(clean) >= 3:
                rings.append(clean)
        if rings:
            out.append(rings)
    return out


def ring_area(ring) -> float:
    """Signed area in square degrees (shoelace)."""
    s = 0.0
    for i, (x1, y1) in enumerate(ring):
        x2, y2 = ring[(i + 1) % len(ring)]
        s += x1 * y2 - x2 * y1
    return s / 2


def ring_centroid(ring) -> tuple[float, float, float]:
    a = 0.0
    cx = cy = 0.0
    for i, (x1, y1) in enumerate(ring):
        x2, y2 = ring[(i + 1) % len(ring)]
        f = x1 * y2 - x2 * y1
        a += f
        cx += (x1 + x2) * f
        cy += (y1 + y2) * f
    a /= 2
    return cx / (6 * a), cy / (6 * a), abs(a)


def inside_ring(x: float, y: float, ring) -> bool:
    hit = False
    n = len(ring)
    for i in range(n):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % n]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            hit = not hit
    return hit


def inside(x: float, y: float, polys) -> bool:
    for rings in polys:
        if inside_ring(x, y, rings[0]) and not any(inside_ring(x, y, h) for h in rings[1:]):
            return True
    return False


def center(polys) -> tuple[float, float]:
    """The centroid of the largest part, or a point surely inside it."""
    biggest = max(polys, key=lambda r: abs(ring_area(r[0])))
    cx, cy, _ = ring_centroid(biggest[0])
    if inside(cx, cy, [biggest]):
        return cx, cy
    # Concave shape: the middle of the widest crossing at the centroid's
    # latitude.
    xs = []
    ring = biggest[0]
    for i in range(len(ring)):
        x1, y1 = ring[i]
        x2, y2 = ring[(i + 1) % len(ring)]
        if (y1 > cy) != (y2 > cy):
            xs.append((x2 - x1) * (cy - y1) / (y2 - y1) + x1)
    xs.sort()
    a, b = max(zip(xs[::2], xs[1::2]), key=lambda s: s[1] - s[0])
    return (a + b) / 2, cy


def area_m2(polys) -> float:
    k = 111_320 * math.cos(math.radians(14.6)) * 110_574
    return sum(abs(ring_area(r[0])) - sum(abs(ring_area(h)) for h in r[1:]) for r in polys) * k


# ------------------------------------------------------------ polyline

def encode(points) -> str:
    """Encoded Polyline Algorithm, precision 1e-5, (lat, lng) order, the
    same as the apps' encodePolyline and PostGIS ST_LineFromEncodedPolyline."""
    out = []
    plat = plng = 0
    for lng, lat in points:
        la, ln = round(lat * 1e5), round(lng * 1e5)
        for v in (la - plat, ln - plng):
            v = ~(v << 1) if v < 0 else v << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        plat, plng = la, ln
    return "".join(out)


# ------------------------------------------------------------ main

def main() -> None:
    layer = json.loads(get(LAYER, {
        "where": f"city_code='{MANILA_CITY_CODE}'",
        "outFields": "brgy_name,psgc_10d",
        "outSR": "4326",
        "f": "geojson",
    }))
    psgc = json.loads(get(PSGC))
    if layer.get("exceededTransferLimit"):
        sys.exit("The layer answer was cut short; ask for fewer at a time.")

    official = {b["name"]: b["psgc10DigitCode"] for b in psgc}
    if len(official) != 897:
        sys.exit(f"PSGC lists {len(official)} barangays for Manila, not 897.")

    barangays, other = [], []
    for f in layer["features"]:
        district, _, name = f["properties"]["brgy_name"].partition(" - ")
        district = DISTRICTS.get(district, district)
        polys = rings_of(f["geometry"])
        item = {
            "name": name,
            "district": district,
            "psgc": f["properties"]["psgc_10d"],
            "polygons": [[encode(r) for r in rings] for rings in polys],
            "_polys": polys,
        }
        (barangays if name in official else other).append(item)

    names = [b["name"] for b in barangays]
    if sorted(names) != sorted(official):
        sys.exit("The layer's barangays do not match the PSGC list.")
    wrong = [b["name"] for b in barangays if b["psgc"] != official[b["name"]]]
    if wrong:
        sys.exit(f"PSGC codes differ for {wrong}.")
    if len(other) != 2:
        sys.exit(f"Expected 2 areas outside any barangay, found {len(other)}.")

    def number(name: str):
        m = re.fullmatch(r"Barangay (\d+)(-A)?", name)
        return (int(m.group(1)), m.group(2) or "") if m else (10_000, name)

    barangays.sort(key=lambda b: number(b["name"]))
    for b in barangays + other:
        b["center"] = center(b["_polys"])
        b["area"] = area_m2(b["_polys"])
        assert inside(*b["center"], b["_polys"]), b["name"]

    # The database file.
    db = {
        "source": SOURCE,
        "barangays": [
            {k: b[k] for k in ("name", "district", "psgc", "polygons")}
            | {"center": [round(b["center"][1], 5), round(b["center"][0], 5)]}
            for b in barangays
        ],
        "other": [
            {"name": o["name"], "district": o["district"], "polygons": o["polygons"]}
            for o in other
        ],
    }
    with io.open(os.path.join(DATA, "manila_barangays.json"), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(db, fh, ensure_ascii=False, separators=(",", ":"))
        fh.write("\n")

    with io.open(os.path.join(DATA, "manila_barangays.csv"), "w", encoding="utf-8", newline="") as fh:
        w = csv.writer(fh, lineterminator="\n")
        w.writerow(["name", "district", "psgc_code", "center_latitude", "center_longitude", "area_m2"])
        for b in barangays:
            w.writerow([b["name"], b["district"], b["psgc"],
                        f"{b['center'][1]:.5f}", f"{b['center'][0]:.5f}", round(b["area"])])

    # The apps' bundled copy.
    lines = [
        "// GENERATED by supabase/data/fetch_barangays.py. Do not edit by hand.",
        f"// Source: {SOURCE}.",
        "",
        "part of 'manila_barangays.dart';",
        "",
        "/// All 897 barangays of the City of Manila, in number order.",
        "const manilaBarangays = <Barangay>[",
    ]
    for b in barangays:
        lat, lng = b["center"][1], b["center"][0]
        lines.append(f"  Barangay('{b['name']}', '{b['district']}', GeoPoint({lat:.5f}, {lng:.5f})),")
    lines += [
        "];",
        "",
        "/// Each barangay's outline (outer rings, encoded polylines), in the",
        "/// same order as [manilaBarangays]. A barangay in several parts has",
        "/// several rings.",
        "const _outlines = <List<String>>[",
    ]
    for b in barangays:
        rings = ", ".join(f"r'{rings[0]}'" for rings in b["polygons"])
        lines.append(f"  [{rings}],")
    lines += [
        "];",
        "",
        "/// Parts of Manila that are in no barangay (Tutuban Mall, Manila North",
        "/// Cemetery).",
        "const _otherOutlines = <String>[",
    ]
    for o in other:
        for rings in o["polygons"]:
            lines.append(f"  r'{rings[0]}',")
    lines += ["];", ""]
    with io.open(DART, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))

    sizes = {p: os.path.getsize(p) for p in (
        os.path.join(DATA, "manila_barangays.json"),
        os.path.join(DATA, "manila_barangays.csv"),
        DART,
    )}
    total = sum(b["area"] for b in barangays + other) / 1e6
    print(f"{len(barangays)} barangays and {len(other)} other areas, {total:.1f} km2 in all")
    for p, n in sizes.items():
        print(f"  {os.path.relpath(p, ROOT)}: {n:,} bytes")


if __name__ == "__main__":
    main()
