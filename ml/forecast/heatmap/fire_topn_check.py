# Objective 2, fire (2026-11-23). Option A: fire heatmap marks only the top-N barangays by KDE (bandwidth
# reused from kde-v3, 400 m). N and the LSTM cut-off chosen on validation
# by balanced accuracy; scored once on test; random same-size baseline.
import sys, json
from pathlib import Path
from collections import defaultdict
from datetime import date, timedelta
import numpy as np
F = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(F)); sys.path.insert(0, str(F / "heatmap"))
import evaluate_heatmap as ev, tune_rule as tr
ev.select_bandwidth = lambda pts: (400, None)  # kde-v3's choice, no CV
import tensorflow as tf
from kde.kde import default_boundaries, load_boundaries
from lstm.prepare_windows import HORIZON, read_csv
v = "mdrrmd"; build = ev.BUILD / v; prep = ev.FORECAST / "data" / "prepared" / v
inc = read_csv(prep / "manila_incidents_prepared.csv"); b = load_boundaries(default_boundaries()); names = list(b)
h = "fire"; data = np.load(build / f"windows_{h}.npz"); ends = [date.fromisoformat(str(e)) for e in data["ends"]]
(_, tb), (va, vb), (ta, tb2) = data["ranges"]; tu = ends[tb - 1] + timedelta(HORIZON)
m = tf.keras.models.load_model(build / f"lstm_{h}.keras")
pv = m.predict(data["x_val"], verbose=0).ravel(); pt = m.predict(data["x_test"], verbose=0).ravel()
days = defaultdict(set)
for r in inc:
    if r["hazard"] == h and r["use_for_kde"] == "yes": days[r["barangay"]].add(date.fromisoformat(r["date"]))
tv = tr.truth_for(ends[va:vb], names, days); tt = tr.truth_for(ends[ta:tb2], names, days)
sp, note = ev.spatial_scores(h, inc, names, b, tu); rel = np.array([sp["kde"][n] for n in names])
print("kde", note, "val pos", int(tv.sum()), "test pos", int(tt.sum()), flush=True)
rk = np.argsort(-rel)
rows = []
for N in [5, 10, 15, 20, 30, 40, 50, 75, 100, 150, 200, 300]:
    d = rel[rk[N - 1]]
    for p in [0.0, 0.3, 0.5, 0.6, 0.7]:
        cv = ev.confusion(tr.predict(pv, rel, p, d), tv)
        rows.append((cv["balanced_accuracy"], N, p, d, cv))
        print(f"N={N:3d} p>={p} val bal={cv['balanced_accuracy']} acc={cv['accuracy']} rec={cv['recall']}", flush=True)
best = max(rows, key=lambda r: (r[0], -r[1]))
_, N, p, d, cv = best
ct = ev.confusion(tr.predict(pt, rel, p, d), tt)
rng = np.random.default_rng(0); rb = []
for _ in range(200):
    pick = np.zeros(len(names), bool); pick[rng.choice(len(names), N, replace=False)] = True
    rb.append(ev.confusion((pt[:, None] >= p) & pick[None, :], tt)["balanced_accuracy"])
rb = np.array(rb)
out = {"chosen_on_validation": {"top_n": N, "probability": p, "kde_score": round(float(d), 4)},
       "validation": cv, "test": ct,
       "random_same_size_test_balanced": {"mean": round(float(rb.mean()), 4), "p95": round(float(np.percentile(rb, 95)), 4), "max": round(float(rb.max()), 4)},
       "kde_bandwidth_m": 400}
print(json.dumps(out, indent=1))
(Path(__file__).parent / "fire_topn_check.json").write_text(
    json.dumps(out, indent=1) + chr(10), encoding="utf-8"
)
