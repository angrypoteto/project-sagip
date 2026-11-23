# Objective 2, fire (2026-11-23). Option B feasibility: does a barangay's recent fire history flag the next
# 72 h's fires? Rule: at risk if >= m fires there in the last K days (known
# at forecast time). K, m chosen on validation by balanced accuracy; test once.
import sys, json, csv
from pathlib import Path
from collections import defaultdict
from datetime import date, timedelta
import numpy as np
F = Path(__file__).resolve().parent.parent
H = 3
inc = list(csv.DictReader(open(F / "data/prepared/mdrrmd/manila_incidents_prepared.csv", encoding="utf-8")))
data = np.load(F / "build/real/mdrrmd/windows_fire.npz")
ends = [date.fromisoformat(str(e)) for e in data["ends"]]
(_, tb), (va, vb), (ta, tb2) = data["ranges"]
fires = defaultdict(list)
for r in inc:
    if r["hazard"] == "fire" and r["use_for_kde"] == "yes":
        fires[r["barangay"]].append(date.fromisoformat(r["date"]))
sys.path.insert(0, str(F))
from kde.kde import default_boundaries, load_boundaries
names = list(load_boundaries(default_boundaries()))
idx = {n: i for i, n in enumerate(names)}
def truth(es):
    t = np.zeros((len(es), len(names)), bool)
    for i, e in enumerate(es):
        for n, ds in fires.items():
            if n in idx and any(e < d <= e + timedelta(H) for d in ds): t[i, idx[n]] = True
    return t
def hist(es, K, m):
    p = np.zeros((len(es), len(names)), bool)
    for i, e in enumerate(es):
        for n, ds in fires.items():
            if n in idx and sum(e - timedelta(K) < d <= e for d in ds) >= m: p[i, idx[n]] = True
    return p
def conf(p, t):
    tp = int((p & t).sum()); fn = int((~p & t).sum()); fp = int((p & ~t).sum()); tn = int((~p & ~t).sum())
    rec = tp / (tp + fn); spec = tn / (tn + fp)
    return {"balanced": round((rec + spec) / 2, 4), "accuracy": round((tp + tn) / (tp + tn + fp + fn), 4), "recall": round(rec, 4), "tp": tp, "fp": fp, "fn": fn}
ev_, et = ends[va:vb], ends[ta:tb2]
tv, tt = truth(ev_), truth(et)
print("positives val/test", int(tv.sum()), int(tt.sum()), "barangays with any fire", len(fires))
best = None
for K in [3, 7, 14, 30, 60, 90, 180, 365, 730]:
    for m in [1, 2, 3]:
        c = conf(hist(ev_, K, m), tv)
        print(f"K={K} m={m} val {c}", flush=True)
        if best is None or c["balanced"] > best[0]["balanced"]: best = (c, K, m)
c, K, m = best
ct = conf(hist(et, K, m), tt)
print("CHOSEN K", K, "m", m, "val", c, "TEST", ct)
# repeat rate: share of fires preceded by a fire in the same barangay within 30/90 days
allf = sorted((d, n) for n, ds in fires.items() for d in ds)
for K in (30, 90, 365):
    rep = sum(any(timedelta(0) < d - e <= timedelta(K) for e in fires[n]) for d, n in allf)
    print(f"fires with an earlier fire in the same barangay within {K} days: {rep} of {len(allf)}")
