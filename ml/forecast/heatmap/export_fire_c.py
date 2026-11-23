"""Model v5 (2026-11-23): v4 with the fire layer of try C
(docs/OBJECTIVE-2-RESULTS.md section 14).

Fire's place map is the KDE of every placed real fire to date (MDRRMD's
plus the public ones of the `recorded` variant: TXTFIRE, DROMIC, news),
500 m, and only the top 300 barangays are kept. run-forecast marks a
barangay's fire moderate if it is one of them or had a fire in the last
180 days, high if both; the fire LSTM's chance is still computed and shown
but does not set the level (it had no skill, sections 9 and 12). Flood is
v4 unchanged. Only per-barangay scores are written: no record, name, or
coordinate.

Usage (from ml/forecast):
  ../../.venv-tf/Scripts/python heatmap/export_fire_c.py
writes supabase/data/forecast_live_v5.json
"""
import csv
import json
import sys
from pathlib import Path

F = Path(__file__).resolve().parent.parent
REPO = F.parent.parent
sys.path.insert(0, str(F))
from kde.kde import (  # noqa: E402
    average_per_barangay, bounding_box, default_boundaries, density_per_km2,
    load_boundaries, make_grid,
)

TOP_N, BANDWIDTH_M, RECENT_DAYS = 300, 500, 180


def placed_fires(variant):
    rows = csv.DictReader(open(F / f"data/prepared/{variant}/manila_incidents_prepared.csv", encoding="utf-8"))
    return [(float(r["latitude"]), float(r["longitude"])) for r in rows
            if r["hazard"] == "fire" and r["use_for_kde"] == "yes"]


points = placed_fires("mdrrmd") + placed_fires("recorded")
bounds = load_boundaries(default_boundaries())
names = list(bounds)
grid = make_grid(bounding_box(bounds))
per = average_per_barangay(grid, density_per_km2(points, grid, BANDWIDTH_M),
                           [{"name": n, "latitude": 0.0, "longitude": 0.0} for n in names], bounds)
rel = sorted(((per[n]["relative"], n) for n in names), reverse=True)
cutoff = rel[TOP_N - 1][0]
top = {n: round(r, 4) for r, n in rel if r >= cutoff}

model = json.loads((REPO / "supabase/data/forecast_live_v4.json").read_text(encoding="utf-8"))
model["version"] = "lstm-kde-v5"
fire = model["hazards"]["fire"]
fire["density"] = top
fire["rule"] = {"kind": "place_or_recent", "density_cutoff": round(cutoff, 4), "recent_days": RECENT_DAYS}
model["data"] = (model.get("data", "") + " Fire layer (v5, 2026-11-23): the top "
                 f"{TOP_N} barangays by the KDE of {len(points)} placed real fires (MDRRMD's and the public "
                 f"TXTFIRE, DROMIC and news fires, {BANDWIDTH_M} m), or a fire there in the last "
                 f"{RECENT_DAYS} days; see docs/OBJECTIVE-2-RESULTS.md section 14.")
out = REPO / "supabase/data/forecast_live_v5.json"
out.write_text(json.dumps(model, separators=(",", ":")) + "\n", encoding="utf-8")
print("points", len(points), "top", len(top), "cutoff", cutoff, "->", out)
