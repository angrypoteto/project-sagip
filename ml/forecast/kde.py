"""The KDE half of the 72-hour forecast (FR4, plan 10.5): where incidents
of each hazard have been densest.

It follows the thesis parameters (CLAUDE.md, "Algorithm parameters"):
  - a Gaussian kernel with haversine distance over the coordinates of past
    incidents of the same hazard
  - the bandwidth chosen from 100, 200, 300, 400, and 500 m by five-fold
    cross-validated log-likelihood
  - a 100 m grid whose densities are averaged per barangay

Densities are reported as incidents per square kilometre over the period of
the records, so they can be read and compared.

Two things are PROVISIONAL and marked so in the summary:
  - Barangay boundaries have not been delivered. Until they are, "per
    barangay" is the average over the grid cells within 400 m of the
    barangay's centre point (the ten sample barangays). Put a GeoJSON file
    of boundaries at ml/forecast/data/barangay_boundaries.geojson (each
    feature with a "name" property) and the cells inside each boundary are
    used instead.
  - How this density and the LSTM probability become a risk level is not
    decided (plan Q22), so no risk levels are written.

Usage:
  python ml/forecast/kde.py
  python ml/forecast/kde.py --incidents path.csv --weather path.csv

Writes ml/forecast/kde_summary.json and
ml/forecast/build/kde_grid_<hazard>.csv (git-ignored).
"""

import argparse
import csv
import json
import math
from pathlib import Path

import numpy as np
from sklearn.model_selection import KFold
from sklearn.neighbors import KernelDensity

from prepare_windows import HAZARDS, MANILA_BOX, clean_incidents, load_weather, read_csv

HERE = Path(__file__).parent
EARTH_RADIUS_M = 6_371_008.8
BANDWIDTHS_M = (100, 200, 300, 400, 500)
FOLDS = 5
GRID_STEP_M = 100
CENTRE_RADIUS_M = 400
SEED = 20261002


def haversine_m(lat1, lng1, lat2, lng2):
    """Great-circle distance in metres. Works on numbers or arrays."""
    p1, p2 = np.radians(lat1), np.radians(lat2)
    dp = p2 - p1
    dl = np.radians(lng2) - np.radians(lng1)
    a = np.sin(dp / 2) ** 2 + np.cos(p1) * np.cos(p2) * np.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * np.arcsin(np.sqrt(a))


def _model(points_deg, bandwidth_m):
    kde = KernelDensity(
        kernel="gaussian",
        metric="haversine",
        algorithm="ball_tree",
        bandwidth=bandwidth_m / EARTH_RADIUS_M,
    )
    return kde.fit(np.radians(points_deg))


def select_bandwidth(points_deg, bandwidths_m=BANDWIDTHS_M, folds=FOLDS, seed=SEED):
    """The bandwidth with the highest mean log-likelihood of held-out
    incidents over the folds. Returns (best, {bandwidth: mean per point})."""
    points_deg = np.asarray(points_deg, dtype=float)
    if len(points_deg) < folds * 2:
        raise ValueError(f"{len(points_deg)} incidents are too few for {folds}-fold cross-validation")
    split = KFold(n_splits=folds, shuffle=True, random_state=seed)
    means = {}
    for bandwidth in bandwidths_m:
        total = 0.0
        for train, test in split.split(points_deg):
            total += _model(points_deg[train], bandwidth).score(np.radians(points_deg[test]))
        means[bandwidth] = total / len(points_deg)
    # On a tie the smaller bandwidth wins (the first in the list).
    best = max(bandwidths_m, key=lambda b: (round(means[b], 9), -b))
    return best, means


def make_grid(box=MANILA_BOX, step_m=GRID_STEP_M):
    """Centres of a grid of step_m cells over the box, as [lat, lng] rows."""
    mid = math.radians((box["south"] + box["north"]) / 2)
    dlat = math.degrees(step_m / EARTH_RADIUS_M)
    dlng = math.degrees(step_m / (EARTH_RADIUS_M * math.cos(mid)))
    lats = np.arange(box["south"] + dlat / 2, box["north"], dlat)
    lngs = np.arange(box["west"] + dlng / 2, box["east"], dlng)
    lat, lng = np.meshgrid(lats, lngs, indexing="ij")
    return np.column_stack([lat.ravel(), lng.ravel()])


def density_per_km2(points_deg, grid_deg, bandwidth_m):
    """Incidents per square kilometre at each grid point: the kernel density
    (which sums to 1 over the sphere, per square radian) times the number
    of incidents, per square kilometre."""
    points_deg = np.asarray(points_deg, dtype=float)
    log_density = _model(points_deg, bandwidth_m).score_samples(np.radians(grid_deg))
    per_square_radian = np.exp(log_density) * len(points_deg)
    return per_square_radian / (EARTH_RADIUS_M / 1000) ** 2


def _inside_ring(lat, lng, ring):
    """Ray casting: which points are inside one ring of [lng, lat] corners."""
    inside = np.zeros(len(lat), dtype=bool)
    xs = np.array([c[0] for c in ring], dtype=float)
    ys = np.array([c[1] for c in ring], dtype=float)
    j = len(ring) - 1
    for i in range(len(ring)):
        crosses = (ys[i] > lat) != (ys[j] > lat)
        with np.errstate(divide="ignore", invalid="ignore"):
            x_at = (xs[j] - xs[i]) * (lat - ys[i]) / (ys[j] - ys[i]) + xs[i]
        inside ^= crosses & (lng < x_at)
        j = i
    return inside


def inside_geometry(grid_deg, geometry):
    """Which grid points fall inside a GeoJSON Polygon or MultiPolygon
    (holes are respected)."""
    lat, lng = grid_deg[:, 0], grid_deg[:, 1]
    polygons = geometry["coordinates"] if geometry["type"] == "MultiPolygon" else [geometry["coordinates"]]
    inside = np.zeros(len(grid_deg), dtype=bool)
    for rings in polygons:
        here = _inside_ring(lat, lng, rings[0])
        for hole in rings[1:]:
            here &= ~_inside_ring(lat, lng, hole)
        inside |= here
    return inside


def average_per_barangay(grid_deg, density, barangays, boundaries=None, radius_m=CENTRE_RADIUS_M):
    """The mean density over each barangay's grid cells: the cells inside
    its boundary when one is given, else those within radius_m of its
    centre. A barangay with no cells gets the density at its centre's
    nearest cell."""
    out = {}
    for b in barangays:
        geometry = (boundaries or {}).get(b["name"])
        if geometry is not None:
            cells = inside_geometry(grid_deg, geometry)
            method = "boundary"
        else:
            distance = haversine_m(b["latitude"], b["longitude"], grid_deg[:, 0], grid_deg[:, 1])
            cells = distance <= radius_m
            method = f"within {radius_m} m of the centre"
        if not cells.any():
            distance = haversine_m(b["latitude"], b["longitude"], grid_deg[:, 0], grid_deg[:, 1])
            cells = distance == distance.min()
            method = "nearest cell"
        out[b["name"]] = {
            "district": b.get("district", ""),
            "mean_per_km2": round(float(density[cells].mean()), 3),
            "cells": int(cells.sum()),
            "area": method,
        }
    top = max((v["mean_per_km2"] for v in out.values()), default=0.0)
    ranked = sorted(out, key=lambda name: -out[name]["mean_per_km2"])
    for rank, name in enumerate(ranked, start=1):
        out[name]["relative"] = round(out[name]["mean_per_km2"] / top, 3) if top > 0 else 0.0
        out[name]["rank"] = rank
    return out


def load_barangays(path):
    return [
        {
            "name": r["name"],
            "district": r.get("district", ""),
            "latitude": float(r["center_latitude"]),
            "longitude": float(r["center_longitude"]),
        }
        for r in read_csv(path)
    ]


def load_boundaries(path):
    """{barangay name: GeoJSON geometry}, or None when there is no file."""
    path = Path(path)
    if not path.exists():
        return None
    features = json.loads(path.read_text(encoding="utf-8"))["features"]
    return {f["properties"]["name"]: f["geometry"] for f in features}


def run(incidents, barangays, boundaries=None, out_dir=None):
    grid = make_grid()
    summary = {}
    for hazard in HAZARDS:
        points = np.array(
            [[r["latitude"], r["longitude"]] for r in incidents if r["hazard"] == hazard],
            dtype=float,
        )
        if len(points) < FOLDS * 2:
            summary[hazard] = {"incidents": int(len(points)), "skipped": "too few incidents"}
            continue
        best, means = select_bandwidth(points)
        density = density_per_km2(points, grid, best)
        cell_km2 = (GRID_STEP_M / 1000) ** 2
        summary[hazard] = {
            "incidents": int(len(points)),
            "bandwidth_m": best,
            "mean_log_likelihood": {str(b): round(float(v), 4) for b, v in means.items()},
            "grid_cells": int(len(grid)),
            "densest_cell_per_km2": round(float(density.max()), 2),
            # Close to the number of incidents when the grid covers them.
            "incidents_under_the_surface": round(float(density.sum() * cell_km2), 1),
            "barangays": average_per_barangay(grid, density, barangays, boundaries),
        }
        if out_dir is not None:
            Path(out_dir).mkdir(parents=True, exist_ok=True)
            with (Path(out_dir) / f"kde_grid_{hazard}.csv").open("w", newline="", encoding="utf-8") as f:
                writer = csv.writer(f, lineterminator="\n")
                writer.writerow(["latitude", "longitude", "incidents_per_km2"])
                for (lat, lng), value in zip(grid, density):
                    writer.writerow([f"{lat:.6f}", f"{lng:.6f}", f"{value:.4f}"])
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--incidents", default=HERE / "data" / "sample_incidents.csv")
    parser.add_argument("--weather", default=HERE / "data" / "sample_weather_daily.csv")
    parser.add_argument("--barangays", default=HERE / "data" / "sample_barangays.csv")
    parser.add_argument("--boundaries", default=HERE / "data" / "barangay_boundaries.geojson")
    args = parser.parse_args()

    # The same cleaning as the LSTM's data preparation, over the same period.
    days, _ = load_weather(read_csv(args.weather))
    incidents, log = clean_incidents(read_csv(args.incidents), days[0], days[-1])
    boundaries = load_boundaries(args.boundaries)
    hazards = run(incidents, load_barangays(args.barangays), boundaries, out_dir=HERE / "build")

    sample = "sample_" in Path(args.incidents).name
    provisional = ["no risk levels: how the density and the LSTM probability combine is not decided (plan Q22)"]
    if boundaries is None:
        provisional.insert(0, f"no barangay boundaries: the average is over the cells within {CENTRE_RADIUS_M} m of each centre")
    summary = {
        "data": "SAMPLE (made up by make_sample_data.py); nothing here is a result" if sample else "as given",
        "provisional": provisional,
        "kernel": "gaussian",
        "distance": "haversine",
        "bandwidths_tried_m": list(BANDWIDTHS_M),
        "folds": FOLDS,
        "grid_step_m": GRID_STEP_M,
        "period": [days[0].isoformat(), days[-1].isoformat()],
        "incident_records": log,
        "hazards": hazards,
    }
    (HERE / "kde_summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    for hazard, h in hazards.items():
        if "skipped" in h:
            print(f"  {hazard}: skipped ({h['skipped']})")
            continue
        first = min(h["barangays"], key=lambda name: h["barangays"][name]["rank"])
        print(
            f"  {hazard}: {h['incidents']} incidents, bandwidth {h['bandwidth_m']} m, "
            f"densest sample barangay {first} ({h['barangays'][first]['mean_per_km2']} per km2)"
        )


if __name__ == "__main__":
    main()
