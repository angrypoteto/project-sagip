"""Daily satellite rainfall over the City of Manila from JAXA's GSMaP, for
training the LSTM (Objective 2, plan 10.5).

Source: GSMaP Gauge-adjusted v6, daily (JAXA Earth API, open data, no
registration; https://data.earth.jaxa.jp). Credit: "GSMaP (JAXA)". Terms:
https://earth.jaxa.jp/en/data/policy/ (free to use, change, and share with
credit). Each day is a Cloud-Optimized GeoTIFF of 0.1 degree cells
(about 11 km); only the 256 x 256 block that holds Manila is read (about
125 KB a day), not the whole file.

The city lies over four cells (120.9 to 121.1 E, 14.5 to 14.7 N). Each
cell's value is kept, and their mean weighted by how much of the city
lies in each cell (CELL_WEIGHTS, from the 897 barangay boundaries; see
cell_weights()).

Time: GSMaP's day D runs 00:00 to 23:59 UTC, which is 08:00 on D to
07:59 on D+1 in Manila (also PAGASA's 8 AM rainfall day). Two thirds of
it falls on D, so it is kept as day D.

Units: the file holds the day's mean rate in mm/h; this writes mm per day
(times 24).

Usage:
  python ml/forecast/data_prep/fetch_gsmap.py --start 2012-01-01 --end 2026-10-24
  (resumes: days already in the output are skipped)

Writes ml/forecast/data/manila_gsmap_daily.csv:
  date,rainfall_total_mm,cell_w_s,cell_e_s,cell_w_n,cell_e_n
"""

import argparse
import csv
import struct
import sys
import time
import urllib.error
import urllib.request
import zlib
from concurrent.futures import ThreadPoolExecutor
from datetime import date, timedelta
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(FORECAST))  # the data_prep, lstm, kde, and heatmap folders import as packages
OUT = FORECAST / "data" / "manila_gsmap_daily.csv"
BASE = (
    "https://s3.ap-northeast-1.wasabisys.com/je-pds/cog/v1/"
    "JAXA.EORC_GSMaP_standard.Gauge.00Z-23Z.v6_daily"
)
# The quarter of the globe that holds the Philippines: 90 to 180 E, 0 to 90 N.
TILE = "1/E090.00-E180.00/E090.00-N00.00-E180.00-N90.00-PRECIP.tiff"
# The four 0.1 degree cells over the city, as (column, row) from the file's
# top-left corner (90 E, 90 N): west/east of 121.0 E, south/north of 14.6 N.
CELLS = {
    "cell_w_s": (309, 754),  # 120.9-121.0 E, 14.5-14.6 N
    "cell_e_s": (310, 754),  # 121.0-121.1 E, 14.5-14.6 N
    "cell_w_n": (309, 753),  # 120.9-121.0 E, 14.6-14.7 N
    "cell_e_n": (310, 753),  # 121.0-121.1 E, 14.6-14.7 N
}
# Share of the city's area in each cell (cell_weights() on the barangay
# boundaries, 2026-10-28).
CELL_WEIGHTS = {"cell_w_s": 0.347, "cell_e_s": 0.174, "cell_w_n": 0.42, "cell_e_n": 0.06}
HEADER_BYTES = 16384
USER_AGENT = "project-sagip (capstone; Manila MDRRMD)"


def _get(url, start=None, end=None, tries=4):
    headers = {"User-Agent": USER_AGENT}
    if start is not None:
        headers["Range"] = f"bytes={start}-{end}"
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if attempt == tries - 1:
                raise
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt == tries - 1:
                raise
        time.sleep(2 * (attempt + 1))
    return None


def _tags(header):
    """The first image's TIFF tags we need: {tag: tuple of values}."""
    e = "<" if header[:2] == b"II" else ">"
    (offset,) = struct.unpack(e + "I", header[4:8])
    (count,) = struct.unpack(e + "H", header[offset : offset + 2])
    sizes = {3: ("H", 2), 4: ("I", 4), 12: ("d", 8)}
    out = {}
    for i in range(count):
        at = offset + 2 + 12 * i
        tag, kind, n = struct.unpack(e + "HHI", header[at : at + 8])
        if kind not in sizes:
            continue
        code, size = sizes[kind]
        if n * size <= 4:
            raw = header[at + 8 : at + 8 + n * size]
        else:
            (pointer,) = struct.unpack(e + "I", header[at + 8 : at + 12])
            raw = header[pointer : pointer + n * size]
            if len(raw) < n * size:
                raise ValueError(f"tag {tag} lies past the first {HEADER_BYTES} bytes")
        out[tag] = struct.unpack(e + code * n, raw)
    return e, out


def read_day(day):
    """{cell: mm per day} for one day, or None if JAXA has no file for it."""
    url = f"{BASE}/{day:%Y-%m}/{day:%d}/{TILE}"
    header = _get(url, 0, HEADER_BYTES - 1)
    if header is None:
        return None
    e, tags = _tags(header)
    width, tile_w, tile_h = tags[256][0], tags[322][0], tags[323][0]
    if tags[259][0] != 8 or tags[339][0] != 3 or tags[258][0] != 32:
        raise ValueError(f"{day}: not deflate float32")
    if tags.get(317, (1,))[0] != 1:
        raise ValueError(f"{day}: a predictor is set; not handled")
    scale, tie = tags[33550], tags[33922]
    if abs(scale[0] - 0.1) > 1e-9 or abs(tie[3] - 90) > 1e-9 or abs(tie[4] - 90) > 1e-9:
        raise ValueError(f"{day}: unexpected grid {scale} {tie}")
    across = -(-width // tile_w)
    blocks = {}
    values = {}
    for name, (col, row) in CELLS.items():
        index = (row // tile_h) * across + col // tile_w
        if index not in blocks:
            start, size = tags[324][index], tags[325][index]
            blocks[index] = zlib.decompress(_get(url, start, start + size - 1))
        at = ((row % tile_h) * tile_w + col % tile_w) * 4
        (rate,) = struct.unpack(e + "f", blocks[index][at : at + 4])
        values[name] = None if rate < 0 or rate != rate else rate * 24
    return values


def weighted(values):
    if any(values[c] is None for c in CELLS):
        return None
    return sum(values[c] * CELL_WEIGHTS[c] for c in CELLS)


def cell_weights():
    """The share of the city in each cell, from the barangay boundaries."""
    from shapely.geometry import box, shape
    from shapely.ops import unary_union

    from kde.kde import default_boundaries, load_boundaries

    city = unary_union([shape(g).buffer(0) for g in load_boundaries(default_boundaries()).values()])
    shares = {}
    for name, (col, row) in CELLS.items():
        west, north = 90 + col * 0.1, 90 - row * 0.1
        shares[name] = city.intersection(box(west, north - 0.1, west + 0.1, north)).area / city.area
    return shares


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=date.fromisoformat, default=date(2012, 1, 1))
    parser.add_argument("--end", type=date.fromisoformat, required=True)
    parser.add_argument("--workers", type=int, default=6)
    parser.add_argument("--weights", action="store_true", help="print the cell weights and stop")
    args = parser.parse_args()
    if args.weights:
        print({k: round(v, 3) for k, v in cell_weights().items()})
        return

    done = {}
    if OUT.exists():
        with OUT.open(newline="", encoding="utf-8") as f:
            done = {r["date"]: r for r in csv.DictReader(f)}
    days = [args.start + timedelta(n) for n in range((args.end - args.start).days + 1)]
    todo = [d for d in days if d.isoformat() not in done]
    print(f"{len(days)} days, {len(todo)} to fetch")

    def fetch(day):
        return day, read_day(day)

    fields = ["date", "rainfall_total_mm", *CELLS]
    missing = []
    with ThreadPoolExecutor(args.workers) as pool:
        for n, (day, values) in enumerate(pool.map(fetch, todo), 1):
            if values is None:
                missing.append(day.isoformat())
            else:
                total = weighted(values)
                done[day.isoformat()] = {
                    "date": day.isoformat(),
                    "rainfall_total_mm": "" if total is None else f"{total:.2f}",
                    **{c: "" if values[c] is None else f"{values[c]:.2f}" for c in CELLS},
                }
            if n % 200 == 0 or n == len(todo):
                _write(done, fields)
                print(f"{n}/{len(todo)} fetched", flush=True)
    _write(done, fields)
    print(f"written {len(done)} days to {OUT}; {len(missing)} without a file: {missing[:10]}")


def _write(done, fields):
    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for key in sorted(done):
            writer.writerow(done[key])


if __name__ == "__main__":
    main()
