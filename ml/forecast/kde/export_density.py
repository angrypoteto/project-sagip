"""Exports the KDE's relative density per barangay for the dashboard's
Hotspots view (the `hazard_density` table, migration hazard_density).

Reads kde_summary.json (from kde.py) and writes
ml/forecast/build/density_insert.sql (git-ignored): one statement that
replaces every row of `hazard_density`. Barangays with no density are left
out (the dashboard paints nothing there). Run it in the Supabase SQL editor
after kde.py.

The model version is 'sample' while kde_summary.json comes from the made-up
records (make_sample_data.py), so the dashboard labels the view a sample.

Usage:
  python ml/forecast/kde/export_density.py [--summary kde/kde_summary_recorded.json]

With the recorded fit (2026-11-02, the live forecast's model lstm-kde-v2) the
rows are labelled kde-v2, so the barangay panel's "past incidents here" is the
same KDE the live forecast uses.
"""

import argparse
import json
from pathlib import Path

HERE = Path(__file__).parent
BUILD = HERE.parent / "build"
DB_HAZARD = {"flood": "flood", "fire": "fire", "storm_surge": "stormSurge", "medical": "medical"}


def quote(text):
    return "'" + str(text).replace("'", "''") + "'"


def main():
    parser = argparse.ArgumentParser()
    # 2026-11-07 (model v3): several summaries at once (MDRRMD's fire and
    # flood, and the Medical layer), a version label, and a JSON copy the
    # database can fetch (supabase/README.md, "Loading model v3").
    parser.add_argument("--summary", action="append", default=None)
    parser.add_argument("--version", default=None)
    parser.add_argument("--json-out", default=None)
    args = parser.parse_args()
    summaries = args.summary or [HERE / "kde_summary.json"]
    rows, records = [], []
    for path in summaries:
        summary = json.loads(Path(path).read_text(encoding="utf-8"))
        sample = str(summary.get("data", "")).startswith("SAMPLE")
        version = args.version or (
            "sample" if sample else ("kde-v2" if "recorded" in Path(path).name else "kde-v1"))
        for hazard, fit in summary["hazards"].items():
            for name, b in fit.get("barangays", {}).items():
                if b["relative"] <= 0:
                    continue
                rows.append(
                    f"({quote(name)}, {quote(b['district'])}, {quote(DB_HAZARD[hazard])}, "
                    f"{b['relative']}, {quote(version)})"
                )
                records.append({"barangay": name, "district": b["district"], "hazard": DB_HAZARD[hazard],
                                "relative": b["relative"], "model_version": version})
    if args.json_out:
        text = json.dumps(records, separators=(",", ":"))
        Path(args.json_out).write_text(text + chr(10), encoding="utf-8")
        print(f"{len(records)} rows -> {args.json_out}")
    BUILD.mkdir(exist_ok=True)
    sql = (
        "begin;\n"
        "delete from public.hazard_density where true;\n"
        "insert into public.hazard_density (barangay, district, hazard, relative, model_version) values\n"
        + ",\n".join(rows)
        + ";\ncommit;\n"
    )
    out = BUILD / "density_insert.sql"
    out.write_text(sql, encoding="utf-8")
    print(f"{len(rows)} rows ({version}) -> {out}")


if __name__ == "__main__":
    main()
