"""How much of each Manila barangay lies in UP NOAH's flood and storm surge
hazard zones (Objective 2, plan 10.5: the spatial half of the heatmap).

Source: UP NOAH's open hazard maps for Metro Manila, downloaded on
2026-10-28 from the Google Drive folder linked on https://noah.up.edu.ph
(Flood/100yr, 25yr, 5yr; Storm Surge/StormSurgeAdvisory1 to 4). License:
Open Data Commons Open Database License (ODbL 1.0); credit "UP NOAH". The
table this writes is derived from them, so it is under the ODbL too.

Each map has three zones: 1 low, 2 medium, 3 high hazard. Flood: from
knee-deep to above the neck, for 5, 25, and 100-year rain (PAGASA's rain
return periods; FLO-2D model). Storm surge: inundation for each storm surge
advisory (SSA 1 up to 2 m, SSA 2 up to 3 m, SSA 3 up to 4 m, SSA 4 over
4 m).

The maps themselves (about 107 MB) stay in ml/forecast/data/noah/, which
git ignores. Re-download them from the folder above to rerun this.

Usage:
  .venv/Scripts/python ml/forecast/data_prep/noah_barangays.py

Writes ml/forecast/data/noah_barangay_hazard.csv: one row per barangay,
the share (0 to 1) of its area in each zone of each map.
"""

import csv
import struct
import sys
from pathlib import Path

from shapely import STRtree, make_valid
from shapely.geometry import Polygon, shape
from shapely.ops import unary_union

FORECAST = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(FORECAST))  # the data_prep, lstm, kde, and heatmap folders import as packages

from kde.kde import default_boundaries, load_boundaries  # noqa: E402

NOAH = FORECAST / "data" / "noah"
OUT = FORECAST / "data" / "noah_barangay_hazard.csv"
MAPS = {
    "flood_5yr": "flood_5yr/MetroManila_Flood_5year.shp",
    "flood_25yr": "flood_25yr/MetroManila_Flood_25year.shp",
    "flood_100yr": "flood_100yr/MetroManila_Flood_100year.shp",
    "ssa1": "ssa1/MetroManila_StormSurge_SSA1.shp",
    "ssa2": "ssa2/MetroManila_StormSurge_SSA2.shp",
    "ssa3": "ssa3/MetroManila_StormSurge_SSA3.shp",
    "ssa4": "ssa4/MetroManila_StormSurge_SSA4.shp",
}
LEVELS = {1: "low", 2: "medium", 3: "high"}


def read_dbf_levels(path):
    """The hazard level (1, 2, 3) of each record, in order."""
    b = path.read_bytes()
    count, header_len, record_len = struct.unpack("<IHH", b[4:12])
    width = b[32 + 16]  # the one field (Var or HAZ)
    return [
        round(float(b[header_len + i * record_len + 1 : header_len + i * record_len + 1 + width].decode("latin1")))
        for i in range(count)
    ]


def _signed_area(ring):
    return sum(x0 * y1 - x1 * y0 for (x0, y0), (x1, y1) in zip(ring, ring[1:])) / 2


def read_polygons(path):
    """Each record of a polygon shapefile as one (multi)polygon. Outer rings
    run clockwise, holes counter-clockwise (the shapefile rule); each hole
    goes into the outer ring that holds it."""
    b = path.read_bytes()
    at = 100
    records = []
    while at < len(b):
        (length,) = struct.unpack(">i", b[at + 4 : at + 8])
        content = b[at + 8 : at + 8 + 2 * length]
        at += 8 + 2 * length
        kind = struct.unpack("<i", content[:4])[0]
        if kind == 0:
            records.append(Polygon())
            continue
        if kind != 5:
            raise ValueError(f"{path.name}: shape type {kind}, expected polygons")
        parts, points = struct.unpack("<ii", content[36:44])
        starts = list(struct.unpack(f"<{parts}i", content[44 : 44 + 4 * parts])) + [points]
        xy = struct.unpack(f"<{2 * points}d", content[44 + 4 * parts : 44 + 4 * parts + 16 * points])
        coords = list(zip(xy[0::2], xy[1::2]))
        outers, holes = [], []
        for s, e in zip(starts, starts[1:]):
            ring = coords[s:e]
            if len(ring) < 4:
                continue
            (outers if _signed_area(ring) < 0 else holes).append(ring)
        shells = [Polygon(r) for r in outers]
        inner = [[] for _ in shells]
        if holes and shells:
            tree = STRtree(shells)
            for ring in holes:
                hole = Polygon(ring)
                point = hole.representative_point()
                hits = [i for i in tree.query(point) if shells[i].contains(point)]
                if hits:
                    inner[min(hits, key=lambda i: shells[i].area)].append(ring)
        polygons = [make_valid(Polygon(r, h)) for r, h in zip(outers, inner)]
        records.append(make_valid(unary_union(polygons)) if polygons else Polygon())
    return records


def barangay_shares(boundaries, zones):
    """{barangay: {level: share of its area}} for one map."""
    out = {}
    for name, geometry in boundaries.items():
        area = geometry.area
        out[name] = {
            level: zone.intersection(geometry).area / area if area else 0.0
            for level, zone in zones.items()
        }
    return out


def main():
    raw = load_boundaries(default_boundaries())
    boundaries = {name: make_valid(shape(g)) for name, g in raw.items()}
    city = unary_union(list(boundaries.values())).buffer(0.002)
    columns = {}
    for key, rel in MAPS.items():
        path = NOAH / rel
        if not path.exists():
            raise SystemExit(f"{path} is missing: download UP NOAH's Metro Manila maps (see the header)")
        levels = read_dbf_levels(path.with_suffix(".dbf"))
        polygons = read_polygons(path)
        # Only the part over the city matters; clipping first keeps it fast.
        zones = {LEVELS[lv]: make_valid(p).intersection(city) for lv, p in zip(levels, polygons)}
        shares = barangay_shares(boundaries, zones)
        for name in boundaries:
            for level in LEVELS.values():
                columns.setdefault(name, {})[f"{key}_{level}"] = shares[name][level]
        print(f"{key}: done", flush=True)
    fields = ["barangay"] + [f"{k}_{lv}" for k in MAPS for lv in LEVELS.values()]
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(fields)
        for name in boundaries:
            writer.writerow([name] + [f"{columns[name][c]:.4f}" for c in fields[1:]])
    print(f"wrote {len(boundaries)} barangays to {OUT}")


if __name__ == "__main__":
    main()
