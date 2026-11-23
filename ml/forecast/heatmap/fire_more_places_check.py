"""Objective 2, fire (2026-11-23). Try C: where fires cluster, fitted on
more real fires. The fire KDE is fitted on MDRRMD's placed fires plus the
public placed fires of the `recorded` variant (TXTFIRE, DROMIC, news;
2021 onward), all only up to the end of the training part. The truth is
still MDRRMD's fires only. Bandwidth (200 to 500 m), how many top
barangays, and an optional "fire there in the last K days" boost are
chosen by balanced accuracy on the validation windows; scored once on the
test windows, beside random barangays of the same number.

Usage (from ml/forecast): ../../.venv-tf/Scripts/python heatmap/fire_more_places_check.py
"""
import csv
import json
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import numpy as np

F = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(F))
from kde.kde import (  # noqa: E402
    average_per_barangay, bounding_box, default_boundaries, density_per_km2,
    load_boundaries, make_grid,
)

H = 3
def rows(v):
    return list(csv.DictReader(open(F / f"data/prepared/{v}/manila_incidents_prepared.csv", encoding="utf-8")))

data = np.load(F / "build/real/mdrrmd/windows_fire.npz")
ends = [date.fromisoformat(str(e)) for e in data["ends"]]
(_, tb), (va, vb), (ta, tb2) = data["ranges"]
train_until = ends[tb - 1] + timedelta(H)
bounds = load_boundaries(default_boundaries()); names = list(bounds); idx = {n: i for i, n in enumerate(names)}

mdrrmd = [r for r in rows("mdrrmd") if r["hazard"] == "fire" and r["use_for_kde"] == "yes"]
public = [r for r in rows("recorded") if r["hazard"] == "fire" and r["use_for_kde"] == "yes"]
fires = defaultdict(list)  # MDRRMD truth and history
for r in mdrrmd:
    fires[r["barangay"]].append(date.fromisoformat(r["date"]))

def pts(rs):
    return [(float(r["latitude"]), float(r["longitude"])) for r in rs if date.fromisoformat(r["date"]) <= train_until]
sets = {"mdrrmd": pts(mdrrmd), "mdrrmd+public": pts(mdrrmd) + pts(public)}
print({k: len(v) for k, v in sets.items()}, "train until", train_until, flush=True)

grid = make_grid(bounding_box(bounds))
blank = [{"name": n, "latitude": 0.0, "longitude": 0.0} for n in names]
scores = {}
for k, p in sets.items():
    for bw in (200, 300, 400, 500):
        per = average_per_barangay(grid, density_per_km2(p, grid, bw), blank, bounds)
        scores[(k, bw)] = np.array([per[n]["relative"] for n in names])
        print("kde", k, bw, flush=True)

def truth(es):
    t = np.zeros((len(es), len(names)), bool)
    for i, e in enumerate(es):
        for n, ds in fires.items():
            if n in idx and any(e < d <= e + timedelta(H) for d in ds):
                t[i, idx[n]] = True
    return t

def recent(es, K):
    p = np.zeros((len(es), len(names)), bool)
    for i, e in enumerate(es):
        for n, ds in fires.items():
            if n in idx and any(e - timedelta(K) < d <= e for d in ds):
                p[i, idx[n]] = True
    return p

def conf(p, t):
    tp = int((p & t).sum()); fn = int((~p & t).sum()); fp = int((p & ~t).sum()); tn = int((~p & ~t).sum())
    rec = tp / (tp + fn); spec = tn / (tn + fp)
    return {"balanced": round((rec + spec) / 2, 4), "accuracy": round((tp + tn) / (tp + tn + fp + fn), 4),
            "recall": round(rec, 4), "tp": tp, "fp": fp, "fn": fn}

ev_, et = ends[va:vb], ends[ta:tb2]
tv, tt = truth(ev_), truth(et)
rv = {K: recent(ev_, K) for K in (0, 90, 180, 365)}
rt = {K: recent(et, K) for K in (0, 90, 180, 365)}
best = None
for (k, bw), s in scores.items():
    order = np.argsort(-s)
    for N in (25, 50, 75, 100, 150, 200, 300, 400):
        top = np.zeros(len(names), bool); top[order[:N]] = True
        for K in (0, 90, 180, 365):
            pv = top[None, :] | (rv[K] if K else False)
            c = conf(np.broadcast_to(pv, tv.shape), tv)
            if best is None or c["balanced"] > best[0]["balanced"]:
                best = (c, k, bw, N, K)
c, k, bw, N, K = best
s = scores[(k, bw)]; top = np.zeros(len(names), bool); top[np.argsort(-s)[:N]] = True
ct = conf(np.broadcast_to(top[None, :] | (rt[K] if K else False), tt.shape), tt)
rng = np.random.default_rng(0); rb = []
for _ in range(200):
    pick = np.zeros(len(names), bool); pick[rng.choice(len(names), N, replace=False)] = True
    rb.append(conf(np.broadcast_to(pick[None, :] | (rt[K] if K else False), tt.shape), tt)["balanced"])
out = {"chosen_on_validation": {"kde_points": k, "bandwidth_m": bw, "top_n": N, "recent_fire_days": K},
       "validation": c, "test": ct,
       "random_same_size_test_balanced": {"mean": round(float(np.mean(rb)), 4), "p95": round(float(np.percentile(rb, 95)), 4)}}
print(json.dumps(out, indent=1))
(Path(__file__).parent / "fire_more_places_check.json").write_text(json.dumps(out, indent=1) + chr(10), encoding="utf-8")
