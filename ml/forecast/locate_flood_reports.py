"""Gives each flooded street corner in data/manila_flood_reports.csv a
position, and writes them as incident records for the forecast.

manila_flood_reports.csv was put together by hand on 2026-10-12 from the
MMDA flood lists that news sites reprinted (GMA, Philstar, and others):
one row for each flooded corner in the City of Manila on a day, with the
link it came from. `page_read` says whether the page itself was read
(yes) or only a search summary of it (no). It is a stand-in for MMDA's
and MDRRMD's own records, and holds only the days that made the news.

A corner is placed where the two streets meet on OpenStreetMap (the
Overpass API finds the points the two roads share; their middle is
used). A corner that cannot be found is left out and printed.

Usage:
  python ml/forecast/locate_flood_reports.py

Writes ml/forecast/data/manila_flood_news.csv.
"""

import csv
import json
import time
import urllib.parse
import urllib.request
from collections import Counter
from pathlib import Path

HERE = Path(__file__).parent
SOURCE = HERE / "data" / "manila_flood_reports.csv"
OUT = HERE / "data" / "manila_flood_news.csv"
CACHE = HERE / "build" / "flood_corners.json"
OVERPASS = "https://overpass-api.de/api/interpreter"
AGENT = "project-sagip capstone research (student project)"
# The City of Manila with a small margin: south, west, north, east.
BOX = "14.53,120.93,14.66,121.04"


def corner(street_a, street_b, cache):
    key = f"{street_a} | {street_b}"
    if key not in cache:
        query = (
            f'[out:json][timeout:60];'
            f'way["highway"]["name"~"{street_a}",i]({BOX})->.a;'
            f'way["highway"]["name"~"{street_b}",i]({BOX})->.b;'
            f"node(w.a)(w.b);out;"
        )
        request = urllib.request.Request(
            OVERPASS,
            data=urllib.parse.urlencode({"data": query}).encode(),
            headers={"User-Agent": AGENT},
        )
        # The public server is often busy: wait and ask again.
        for attempt in range(5):
            try:
                with urllib.request.urlopen(request, timeout=90) as response:
                    nodes = json.load(response)["elements"]
                break
            except OSError:
                if attempt == 4:
                    raise
                time.sleep(15 * (attempt + 1))
        cache[key] = (
            [
                round(sum(n["lat"] for n in nodes) / len(nodes), 5),
                round(sum(n["lon"] for n in nodes) / len(nodes), 5),
                len(nodes),
            ]
            if nodes
            else None
        )
        CACHE.parent.mkdir(parents=True, exist_ok=True)
        CACHE.write_text(json.dumps(cache, indent=1, ensure_ascii=False), encoding="utf-8")
        time.sleep(3)
    return cache[key]


def main():
    cache = json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}
    with SOURCE.open(newline="", encoding="utf-8") as f:
        reports = list(csv.DictReader(f))

    rows, missing = [], []
    for n, report in enumerate(reports, 1):
        found = corner(report["street_a"], report["street_b"], cache)
        if found is None:
            missing.append(f"{report['date']} {report['street_a']} / {report['street_b']}")
            continue
        rows.append(
            {
                "incident_id": f"FLD-{report['date'].replace('-', '')}-{n:03d}",
                "date": report["date"],
                "hazard": "flood",
                "latitude": found[0],
                "longitude": found[1],
                "precision": "street",
                "place": f"{report['street_a']} at {report['street_b']}",
                "title": report["as_reported"],
                "source_url": report["source_url"],
                "page_read": report["page_read"],
            }
        )

    with OUT.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    days = sorted({r["date"] for r in rows})
    print(f"{len(rows)} flooded corners on {len(days)} days, {days[0]} to {days[-1]}")
    print("by year:", dict(sorted(Counter(d[:4] for d in days).items())), "(days)")
    print("page read:", dict(Counter(r["page_read"] for r in rows)))
    print("not found on the map:", missing or "none")


if __name__ == "__main__":
    main()
