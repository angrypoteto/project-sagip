# Made-up data (archived 2026-11-07)

These files were written by the team and Claude to build and test the
pipelines before real records existed. **They are not used for training any
more** (Joshua, 2026-11-07: "add all the made up data somewhere in the folder
so we can check it later on if needed but don't use it for now").

| Folder | Files | Was used for |
|---|---|---|
| `forecast/` | `sample_weather_daily.csv`, `sample_incidents.csv`, `sample_barangays.csv` (`ml/forecast/data_prep/make_sample_data.py`) | The first forecast model, `lstm-kde-v1` (inactive since 2026-11-02) |
| `classifier/` | `sample_reports.csv` (1,200 made-up crowd report descriptions, `ml/classifier/make_sample_dataset.py`), `handwritten_check.csv` (80 written apart) | The placeholder classifier `v1-sample` (FR12), still the active model on the hosted project until the team's labelled set (`ml/classifier/TEAM-LABELLING.md`) or MDRRMD's descriptions arrive |

The scripts above still read and write here when run by hand, so nothing
is lost. MDRRMD's real records are in `ml/datasets/mdrrmd/` (not in git).
