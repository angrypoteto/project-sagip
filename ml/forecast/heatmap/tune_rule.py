"""Objective 2 experiment: choose the heatmap's "at risk" cut-off on the
validation part only, then score it once on the test part.

The provisional rule (plan Q22) marks a barangay at risk when the LSTM's
chance of an incident in Manila and the barangay's KDE score both pass
fixed cut-offs. Here, per hazard, the two cut-offs (chance p, KDE score d)
are chosen from a grid by the **balanced accuracy on the validation
windows** (the 15% before the test part), never by the test part, and
never by plain accuracy: plain accuracy would always choose "nothing at
risk", which scores about 99.8% and catches no incident. The chosen rule is
then scored on the test windows, beside the provisional rule and "nothing
at risk".

Usage (from ml/forecast):
  ../../.venv-tf/Scripts/python heatmap/tune_rule.py --variant mdrrmd

Writes heatmap/heatmap_tuned_<variant>.json.
"""

import argparse
import json
import sys
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import numpy as np

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE))

import evaluate_heatmap as ev  # noqa: E402
import tensorflow as tf  # noqa: E402
from kde.kde import default_boundaries, load_boundaries  # noqa: E402
from lstm.prepare_windows import HORIZON, read_csv  # noqa: E402

P_GRID = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
D_GRID = [0.05, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 0.95]


def truth_for(ends, names, days_by_barangay):
    t = np.zeros((len(ends), len(names)), dtype=bool)
    for i, end in enumerate(ends):
        ahead = {end + timedelta(k) for k in range(1, HORIZON + 1)}
        for j, n in enumerate(names):
            t[i, j] = bool(days_by_barangay[n] & ahead)
    return t


def predict(prob, relative, p, d):
    return (prob[:, None] >= p) & (relative[None, :] >= d)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", default="mdrrmd")
    variant = parser.parse_args().variant
    build = ev.BUILD / variant
    prepared = ev.FORECAST / "data" / "prepared" / variant
    incidents = read_csv(prepared / "manila_incidents_prepared.csv")
    boundaries = load_boundaries(default_boundaries())
    names = list(boundaries)
    out = {
        "method": "cut-offs chosen by balanced accuracy on the validation windows; scored once on the test windows",
        "variant": variant,
        "horizon_days": HORIZON,
        "hazards": {},
    }
    for hazard in ("flood", "fire"):
        data = np.load(build / f"windows_{hazard}.npz")
        ends = [date.fromisoformat(str(e)) for e in data["ends"]]
        (_, train_b), (val_a, val_b), (test_a, test_b) = data["ranges"]
        train_until = ends[train_b - 1] + timedelta(HORIZON)
        model = tf.keras.models.load_model(build / f"lstm_{hazard}.keras")
        p_val = model.predict(data["x_val"], verbose=0).ravel()
        p_test = model.predict(data["x_test"], verbose=0).ravel()

        days = defaultdict(set)
        for r in incidents:
            if r["hazard"] == hazard and r["use_for_kde"] == "yes":
                days[r["barangay"]].add(date.fromisoformat(r["date"]))
        t_val = truth_for(ends[val_a:val_b], names, days)
        t_test = truth_for(ends[test_a:test_b], names, days)

        spatial, note = ev.spatial_scores(hazard, incidents, names, boundaries, train_until)
        layers = {}
        for layer, score in spatial.items():
            rel = np.array([score[n] for n in names])
            best = None
            for p in P_GRID:
                for d in D_GRID:
                    c = ev.confusion(predict(p_val, rel, p, d), t_val)
                    key = (c["balanced_accuracy"], c["accuracy"])
                    if best is None or key > best[0]:
                        best = (key, p, d, c)
            _, p, d, val_c = best
            provisional = np.array(
                [[ev.risk_level(x, r) != "low" for r in rel] for x in p_test]
            )
            layers[layer] = {
                "chosen_on_validation": {"probability": p, "kde_score": d},
                "validation": val_c,
                "test_tuned": ev.confusion(predict(p_test, rel, p, d), t_test),
                "test_provisional_rule": ev.confusion(provisional, t_test),
            }
            print(hazard, layer, "p>=", p, "d>=", d,
                  "val bal", val_c["balanced_accuracy"],
                  "test acc/bal/recall", layers[layer]["test_tuned"]["accuracy"],
                  layers[layer]["test_tuned"]["balanced_accuracy"],
                  layers[layer]["test_tuned"]["recall"])
        out["hazards"][hazard] = {
            "validation_days": [ends[val_a].isoformat(), ends[val_b - 1].isoformat()],
            "test_days": [ends[test_a].isoformat(), ends[test_b - 1].isoformat()],
            "validation_barangay_days_with_incident": int(t_val.sum()),
            "test_barangay_days_with_incident": int(t_test.sum()),
            "spatial": note,
            "layers": layers,
            "test_nothing_at_risk": ev.confusion(np.zeros_like(t_test), t_test),
        }
    (HERE / f"heatmap_tuned_{variant}.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
