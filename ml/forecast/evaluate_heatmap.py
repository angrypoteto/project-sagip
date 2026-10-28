"""Objective 2, step 3: how accurate the 72-hour risk heatmap is, per
barangay, on the test part (the last 15% of the windows, never seen in
training).

For each test day t and each of the 897 barangays the heatmap says
"at risk" (moderate or high) or not, from two halves:
  - the LSTM's probability of at least one incident in the city on days
    t+1 to t+3 (train_lstm.py, build/real/lstm_<hazard>.keras)
  - the barangay's spatial score, from 0 to 1 (1 = the riskiest barangay):
      kde    the KDE of the incidents placed at a barangay or street, fitted
             only on incidents up to the end of the training part (thesis
             method: Gaussian, haversine, bandwidth by 5-fold CV)
      noah   (flood only) the share of the barangay in UP NOAH's medium or
             high flood zones for 25-year rain, scaled to the highest
      blend  (flood only) the mean of the two
and the provisional rule of run_forecast.py (plan Q22) turns them into a
level. The truth: a placed incident of that hazard in that barangay on
days t+1 to t+3. Incidents with no single point (district-only fires,
city-wide flood days) cannot be checked per barangay and are left out of
the truth.

Usage (from ml/forecast, after prepare_real.py and train_lstm.py):
  ../../.venv-tf/Scripts/python evaluate_heatmap.py

Writes heatmap_metrics_real.json.
"""

import json
import os
from collections import defaultdict
from datetime import date, timedelta
from pathlib import Path

import numpy as np

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")

import tensorflow as tf  # noqa: E402

from kde import (  # noqa: E402
    average_per_barangay,
    bounding_box,
    default_boundaries,
    density_per_km2,
    load_boundaries,
    make_grid,
    select_bandwidth,
)
from prepare_windows import HORIZON, read_csv  # noqa: E402

HERE = Path(__file__).parent
BUILD = HERE / "build" / "real"
NOAH_MAP = "flood_25yr"


def risk_level(probability, relative):
    """run_forecast.py's provisional rule (plan Q22)."""
    if probability >= 0.5 and relative >= 0.5:
        return "high"
    if (probability >= 0.5 and relative >= 0.2) or (probability >= 0.25 and relative >= 0.5):
        return "moderate"
    return "low"


def confusion(pred, truth):
    pred, truth = np.asarray(pred, bool), np.asarray(truth, bool)
    tp = int((pred & truth).sum())
    tn = int((~pred & ~truth).sum())
    fp = int((pred & ~truth).sum())
    fn = int((~pred & truth).sum())
    n = tp + tn + fp + fn
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    specificity = tn / (tn + fp) if tn + fp else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return {
        "cells": n,
        "accuracy": round((tp + tn) / n, 4),
        "balanced_accuracy": round((recall + specificity) / 2, 4),
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "confusion": {"tp": tp, "fp": fp, "fn": fn, "tn": tn},
    }


def spatial_scores(hazard, incidents, names, boundaries, train_until):
    """{variant: {barangay: 0..1}} using only incidents up to train_until."""
    points = [
        (float(r["latitude"]), float(r["longitude"]))
        for r in incidents
        if r["hazard"] == hazard and r["use_for_kde"] == "yes" and date.fromisoformat(r["date"]) <= train_until
    ]
    out = {}
    note = {"kde_points": len(points)}
    if len(points) >= 10:
        bandwidth, _ = select_bandwidth(points)
        grid = make_grid(bounding_box(boundaries))
        density = density_per_km2(points, grid, bandwidth)
        barangays = [{"name": n, "latitude": 0.0, "longitude": 0.0} for n in names]
        per = average_per_barangay(grid, density, barangays, boundaries)
        out["kde"] = {n: per[n]["relative"] for n in names}
        note["kde_bandwidth_m"] = bandwidth
    else:
        note["kde"] = "too few placed incidents in the training part to fit a KDE (5-fold CV needs 10)"
    if hazard == "flood":
        rows = {r["barangay"]: r for r in read_csv(HERE / "data" / "noah_barangay_hazard.csv")}
        raw = {n: float(rows[n][f"{NOAH_MAP}_medium"]) + float(rows[n][f"{NOAH_MAP}_high"]) for n in names}
        top = max(raw.values()) or 1.0
        out["noah"] = {n: v / top for n, v in raw.items()}
        if "kde" in out:
            out["blend"] = {n: (out["kde"][n] + out["noah"][n]) / 2 for n in names}
    return out, note


def main():
    incidents = read_csv(HERE / "data" / "prepared" / "manila_incidents_prepared.csv")
    boundaries = load_boundaries(default_boundaries())
    names = list(boundaries)
    result = {
        "data": "public records standing in for PAGASA's and MDRRMD's (prepare_real.py)",
        "rule": "at risk = moderate or high by run_forecast.py's provisional rule (plan Q22)",
        "truth": "a placed incident of the hazard in the barangay on days t+1 to t+3",
        "hazards": {},
    }
    for hazard in ("flood", "fire"):
        data = np.load(BUILD / f"windows_{hazard}.npz")
        ends = [date.fromisoformat(str(e)) for e in data["ends"]]
        (_, train_b), _, (test_a, test_b) = data["ranges"]
        train_until = ends[train_b - 1] + timedelta(HORIZON)
        test_ends = ends[test_a:test_b]
        model = tf.keras.models.load_model(BUILD / f"lstm_{hazard}.keras")
        probability = model.predict(data["x_test"], verbose=0).ravel()

        truth_days = defaultdict(set)
        for r in incidents:
            if r["hazard"] == hazard and r["use_for_kde"] == "yes":
                truth_days[r["barangay"]].add(date.fromisoformat(r["date"]))
        truth = np.zeros((len(test_ends), len(names)), dtype=bool)
        for i, t in enumerate(test_ends):
            ahead = {t + timedelta(k) for k in range(1, HORIZON + 1)}
            for j, n in enumerate(names):
                truth[i, j] = bool(truth_days[n] & ahead)

        spatial, note = spatial_scores(hazard, incidents, names, boundaries, train_until)
        variants = {}
        for variant, score in spatial.items():
            relative = np.array([score[n] for n in names])
            pred = np.array([[risk_level(p, r) != "low" for r in relative] for p in probability])
            variants[variant] = confusion(pred, truth)
        variants["nothing_at_risk"] = confusion(np.zeros_like(truth), truth)
        result["hazards"][hazard] = {
            "test_days": [test_ends[0].isoformat(), test_ends[-1].isoformat()],
            "test_windows": len(test_ends),
            "barangay_days_with_a_placed_incident": int(truth.sum()),
            "spatial": note,
            "variants": variants,
        }
        print(hazard, json.dumps({k: (v["accuracy"], v["balanced_accuracy"], v["recall"]) for k, v in variants.items()}))
    (HERE / "heatmap_metrics_real.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
