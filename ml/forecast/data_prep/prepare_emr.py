"""MDRRMD's emergency medical response (EMR) records as points for the
Heatmap's Medical layer (Joshua, 2026-11-07: "Medical heatmap layer"). No
forecast: medical calls are not a forecast hazard in the thesis; the KDE of
past calls shows where they cluster (kde.py --hazards medical).

Reads   ml/datasets/mdrrmd/2025/2025EMR_Records.csv, 2026/2026EMR_Records.csv
        (MDRRMD's, never in git)
Writes  ml/forecast/data/prepared/mdrrmd/manila_medical_prepared.csv
        (git-ignored): incident_id, date, hazard, latitude, longitude,
        barangay, use_for_kde, kind. Only the date, the point, the barangay,
        and the type of call: no names, no free-text location, no vehicles.

Kept: medical calls and road accidents inside the City of Manila's
barangays (the emergencies). Left out: medical standby (crews posted at
events) and patient transport (scheduled transfers), which would mark event
venues and hospitals rather than where emergencies happen; calls outside
Manila or without a readable date. Each record is one call: nothing is
merged.

Usage (from ml/forecast):
  ../../.venv/Scripts/python data_prep/prepare_emr.py
"""

import csv
import re
import sys
from collections import Counter
from datetime import date
from pathlib import Path

FORECAST = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(FORECAST))

from data_prep.prepare_real import Locator  # noqa: E402

MDRRMD = FORECAST.parent / "datasets" / "mdrrmd"
FILES = ["2025/2025EMR_Records.csv", "2026/2026EMR_Records.csv"]
EMERGENCIES = {"Medical Call", "Vehicular / Road Accident"}
OUT = FORECAST / "data" / "prepared" / "mdrrmd" / "manila_medical_prepared.csv"


def day(text):
    m = re.match(r"\s*(\d{1,2})/(\d{1,2})/(\d{4})", text or "")
    if not m:
        return None
    try:
        return date(int(m[3]), int(m[1]), int(m[2]))
    except ValueError:
        return None


def main():
    locator = Locator()
    rows, unreadable, outside = [], 0, 0
    kinds = Counter()
    total = 0
    for rel in FILES:
        with (MDRRMD / rel).open(encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                total += 1
                d = day(r.get("DATE AND TIME", ""))
                try:
                    lat, lng = float(r["y"]), float(r["x"])
                except (KeyError, ValueError):
                    unreadable += 1
                    continue
                if d is None:
                    unreadable += 1
                    continue
                brgy = locator.barangay(lat, lng)
                if brgy is None:
                    outside += 1
                    continue
                kind = (r.get("TYPE OF EMR") or "").strip() or "unknown"
                kinds[kind] += 1
                if kind not in EMERGENCIES:
                    continue
                rows.append({
                    "incident_id": f"mdrrmd-emr-{rel[:4]}-{r['ObjectID']}", "date": d.isoformat(),
                    "hazard": "medical", "latitude": f"{lat:.5f}", "longitude": f"{lng:.5f}",
                    "barangay": brgy, "use_for_kde": "yes", "kind": kind,
                })
    rows.sort(key=lambda r: r["date"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]), lineterminator="\n")
        w.writeheader()
        w.writerows(rows)
    print(f"read {total}; kept {len(rows)} emergencies inside Manila; outside Manila {outside}; "
          f"unreadable {unreadable}")
    print(f"from {rows[0]['date']} to {rows[-1]['date']}; by type {dict(kinds)}")


if __name__ == "__main__":
    main()
