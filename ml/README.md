# ml/

Data preparation and model training for S.A.G.I.P. (plan sections 10.2 to 10.5). Nothing here runs in the apps; the apps and the database use what these scripts export.

| Folder | What it makes | Used by |
|---|---|---|
| `road_graph/` | The directed Manila road graph for Dijkstra (`packages/shared/assets/road_graph/manila_drive_v1.bin`) and the networkx reference answers for its test | `RoadGraph`, `RoadRouter`, and `RoadNetworkSuggester` in `packages/shared` |
| `forecast/` | The data preparation for the LSTM (cleaned records, 14-day windows, chronological split, class weights, baselines), the LSTM itself (thesis architecture, with a TFLite copy), and the KDE surfaces with their per-barangay averages, all on made-up sample data for now | Once plan Q22 is decided, the rows in `barangay_forecast` that D8 and R7 show |
| `classifier/` | The incident type classifier for crowd reports (FR12): `packages/shared/assets/classifier/incident_classifier_v1.json`, the reference answers for its tests, `metrics.json`, and the SQL that loads the model into the database | `private.classify_report` in the database (the trigger on `crowd_report`) and `IncidentClassifier` in `packages/shared` |

Still to come: the real records, and turning the LSTM probability and the KDE density into risk levels (plan Q22).

## Setup

Python 3.12 or newer. Use a virtual environment in the repo root (git-ignored):

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r ml/requirements-road-graph.txt   # Windows
.venv/Scripts/python -m pip install -r ml/requirements-classifier.txt   # only for the classifier
.venv/Scripts/python -m pip install -r ml/requirements-forecast.txt     # only for the forecast

# The LSTM needs TensorFlow, which has no build for Python 3.14: a second
# environment on Python 3.12 (installed on Joshua's machine on 2026-10-03).
py -3.12 -m venv .venv-tf
.venv-tf/Scripts/python -m pip install -r ml/requirements-lstm.txt
# .venv/bin/python on macOS and Linux
```

## Road graph

```bash
.venv/Scripts/python ml/road_graph/build_road_graph.py   # downloads Manila from OpenStreetMap, about 30 s
.venv/Scripts/python ml/road_graph/make_reference.py     # refreshes packages/shared/test/fixtures/road_graph_reference.json
cd packages/shared && flutter test test/road_graph_test.dart
```

- **Area:** the City of Manila boundary plus 1.5 km, drivable roads (`network_type="drive"`), kept to the largest strongly connected part so every intersection can reach every other one.
- **Edge weight:** estimated travel time = length / speed for the road class (`SPEED_KMH` in the script). The speeds are provisional; tune them with MDRRMD's dispatch records (thesis Table 3.1 item 2). OSM `maxspeed` tags are ignored.
- **Rebuilding changes the graph** (OSM is edited every day), so node numbers change: always run `make_reference.py` after a rebuild, and bump the file name (`_v2`) if the format changes.
- **License:** map data (c) OpenStreetMap contributors, available under the Open Database License (ODbL 1.0). The graph file is a derived database and stays under the ODbL; credit OpenStreetMap wherever routes are shown (the maps already show the credit).

## Incident type classifier

```bash
.venv/Scripts/python ml/classifier/make_sample_dataset.py   # only to rebuild the sample set
.venv/Scripts/python ml/classifier/train_classifier.py      # trains, evaluates, exports
cd packages/shared && flutter test test/incident_classifier_test.dart
```

- **What it is:** TF-IDF over word unigrams and bigrams (the thesis parameters), then multinomial logistic regression over flood, fire, medical, and structural. Lowercase; a word is two or more letters or digits (`[a-zñ0-9]{2,}`); at most 600 terms that appear in two or more descriptions.
- **The data is made up.** `data/sample_reports.csv` holds 1,200 descriptions (300 per type) built by `make_sample_dataset.py` from phrases written for development in English, Filipino, and Taglish. **They are not MDRRMD records.** `data/handwritten_check.csv` holds 80 more, written separately and not from those phrases. Replace `sample_reports.csv` with the real labelled descriptions (thesis Table 3.1 item 6, columns `description,label`), bump `VERSION` in the script, and retrain.
- **The scores are not results.** `metrics.json` records them so the pipeline can be seen working: 0.99 on the held-out fifth of the sample (the model has seen the same phrases, so this says little) and 0.84 on the handwritten check (closer to honest, but still one person's writing, and the vocabulary size was picked while looking at it). Neither belongs in Chapter 4. The file also holds per-type precision, recall, and F1, the confusion matrices, the no-skill baseline (0.25), and 5-fold cross-validation.
- **Not sure means no tag.** Below `MIN_CONFIDENCE` (0.5) a report is left untagged. On the handwritten check 72 of 80 get a tag, and 89% of those are right.
- **What it writes:** the model for Dart (`packages/shared/assets/classifier/`), 38 reference cases (`packages/shared/test/fixtures/classifier_reference.json`), `metrics.json`, and `build/classifier_model.sql` (git-ignored) for a migration. The export is rounded to 5 decimals and checked against scikit-learn itself (largest difference 0.000003).
- **Three implementations, one answer:** `classify()` in the training script, `IncidentClassifier` in Dart, and `private.classify_report` in the database must all give the numbers in the reference file. The Dart test and the RLS test check this; rerun both after retraining and update the cases in `supabase/tests/rls_test.sql`.

## Forecast on real data: what is in and what is still needed (from 2026-10-12)

Joshua decided on 2026-10-12 that the forecast must be real, by the thesis's method. The models in `build/` were trained on made-up sample data and say nothing about Manila. To retrain them, three inputs are needed:

| Input | File | State |
|---|---|---|
| Daily rainfall total, wettest hour, highest wind | `forecast/data/manila_weather_daily.csv` | **Real**, 2021-01-01 to 2026-10-05, from Open-Meteo's archive (ERA5 reanalysis, CC BY 4.0) by `fetch_weather.py`. A reanalysis smooths local downpours and shows light rain on many days; PAGASA's own daily records for Port Area would be better if the team can get them |
| Typhoon signal and storm surge per day | `forecast/data/manila_signals.csv` (`date,typhoon_signal,storm_surge_m`, only the days that had one) | **Missing.** From PAGASA's records: every day from 2021 on when a wind signal was up over Manila (the highest that day) or a storm surge was warned of for Manila Bay (the height in meters). Then run `fetch_weather.py ... --signals` |
| Past incidents | a CSV like `forecast/data/sample_incidents.csv`: `incident_id,date,hazard,latitude,longitude` | **Missing.** From MDRRMD: every flood, fire, and storm surge incident, with its date, its type, and where (coordinates, or the barangay or street so it can be placed). Two years or more, the same years as the weather. No names or phone numbers |

Until the last two arrive, `prepare_windows.py` refuses the real weather file (the two columns are empty), on purpose. With them: `prepare_windows.py --weather ... --incidents ...`, `kde.py`, `train_lstm.py`, `export_live.py`, then load the model on the hosted project.

The live input, once there is a real model: PAGASA's signal and surge are already kept as they change (`weather_alert`, real rows since 2026-10-03). The daily rainfall total, the wettest hour, and the wind have to come from the same source the model was trained on, so `run-forecast` will read the last 14 days from Open-Meteo (not built yet; it is a feed the thesis does not name, to be confirmed by the team).

### Incident leads from public news (2026-10-12)

`forecast/data/manila_incident_leads.csv` lists what a first search of news sites gave for Manila from 2021 on: 33 fires and 7 flood days, each with a date, a place as the report named it, and a link. **Every row is unchecked** (`checked` is `no`): the dates and places come from search summaries, two already disagree with their own links, and none has coordinates. No storm surge incident was found for these years. It is far too little to train on (BFP counted 212 structural fires in Manila in 2021 alone), and it holds only what made the news. It is a start for the Data role: open each link, correct the row, set `checked` to `yes`, and add rows from BFP-NCR's and MMDA's own posts. It is not read by any script.

### Incidents from public news, placed on the map (2026-10-12)

Joshua asked for the incident data to be built from public sources while MDRRMD's records are asked for. Two files, both real reports with a link each, both only the part of what happened that made the news:

| File | What | How it was made |
|---|---|---|
| `forecast/data/manila_fire_news.csv` | 131 fires in the City of Manila, 2012-02 to 2025-01 (about ten a year; none for 2017 and 2018, and the archive stops in March 2025). 23 placed by barangay, 43 by street, 65 only by district | `collect_fire_news.py` reads Asia Fire News (Tokyo University of Science's archive of fire reports; every entry mentioning Manila), `locate_fire_news.py` keeps the city's and places them. The date is the report's: the day of the fire or the day after |
| `forecast/data/manila_flood_news.csv` | 56 flooded street corners on 17 days, 2021-07 to 2026-08 | `forecast/data/manila_flood_reports.csv` was put together by hand from the MMDA flood lists that GMA, Philstar, and others reprinted (`page_read` says whether the page itself was read: 39 yes, 17 from a search summary only); `locate_flood_reports.py` places each corner where the two streets meet on OpenStreetMap |

What this is not: a record of incidents. BFP counted 212 structural fires in Manila in 2021 alone; this has 8 for that year. Floods before 2021 were not gathered, and the corners are MMDA's road watch points (España, Taft, Roxas, Rizal Avenue), not homes. No storm surge incident was found. A model trained on it learns when and where incidents get reported. Nothing has been trained on it yet.

Still missing before training: the typhoon signal and storm surge days (`manila_signals.csv`). `manila_weather_daily.csv` now runs from 2012-01-01.

## Forecast: data preparation and KDE (plan 10.5)

```bash
.venv/Scripts/python ml/forecast/make_sample_data.py    # only to rebuild the sample data
cd ml/forecast
../../.venv/Scripts/python prepare_windows.py            # cleaning, windows, split, class weights, baselines
../../.venv/Scripts/python kde.py                        # bandwidth by 5-fold CV, 100 m grid, per-barangay averages
../../.venv/Scripts/python -m unittest test_forecast     # 15 checks; the 2 LSTM ones run only in .venv-tf
../../.venv-tf/Scripts/python train_lstm.py              # the LSTM, about a minute on a laptop CPU
../../.venv-tf/Scripts/python run_forecast.py            # one forecast run for all 897 barangays (writes build/forecast_insert.sql)
```

- **The data is made up.** `data/sample_weather_daily.csv` (three years of daily rain, wind signal, wind, and storm surge) and `data/sample_incidents.csv` (floods, fires, and storm surge incidents around a few made-up hotspots) come from `make_sample_data.py`, by rules written in its header: floods follow heavy rain, fires peak in the dry months, surge incidents happen on surge days. A few bad rows are added on purpose. **They are not PAGASA or MDRRMD records, and nothing measured on them is a result.** `data/sample_barangays.csv` holds the ten sample barangays of the database.
- **Real data:** the same columns. Weather: `date,rainfall_total_mm,rainfall_max_hourly_mm,typhoon_signal,max_wind_kph,storm_surge_m`, one row for every day of the period (a missing or repeated day, or a value out of range, stops the run with the line number; a silent gap would shift every window). Incidents: `incident_id,date,hazard,latitude,longitude` with `hazard` one of `flood`, `fire`, `storm_surge`. Run both scripts with `--weather` and `--incidents`. The storm surge column is a height in metres (what PAGASA's surge advisories give); if the Data role only has the advisory number, change the range in `WEATHER_RANGES`.
- **Cleaning** (`clean_incidents`): removes unreadable dates, dates outside the weather period, unknown hazards, missing coordinates, points outside a box around Manila (until the boundaries arrive), and the same hazard at the same spot on the same day; every count is in the summary (plan 10.5: log what was kept and removed).
- **Windows** (`prepare_windows.py`, the thesis parameters): six daily features over 14 days; the label of the window ending on day *t* is 1 when at least one incident of that hazard happens on days *t+1* to *t+3*; split 70/15/15 in time order, dropping the 3 windows before each split point (their labels look into the next part); features scaled with the training part only; class weights inversely proportional to class frequency. Writes `build/windows_<hazard>.npz` (git-ignored) for the LSTM, and `prep_summary.json` with the counts and three baselines on validation and test: always the more common class, "an incident in the last 3 days means one in the next 3", and logistic regression on the whole window. The LSTM must beat the third to be worth its weight (plan Q23).
- **KDE** (`kde.py`, the thesis parameters): Gaussian kernel with haversine distance (scikit-learn's `KernelDensity` on radians), the bandwidth chosen from 100 to 500 m by 5-fold cross-validated log-likelihood, a 100 m grid over Manila, densities in incidents per square kilometre over the period, averaged per barangay with a rank and a value relative to the densest. Writes `kde_summary.json` and `build/kde_grid_<hazard>.csv`.
- **Per barangay** (since 2026-10-03): the KDE averages the 100 m cells inside each of the 897 barangay boundaries in `supabase/data/manila_barangays.json`, over a grid covering the whole city (876 barangays by their own cells; 21 that are smaller than a cell take the nearest cell). A GeoJSON at `data/barangay_boundaries.geojson` (features with a `name` property) takes precedence.
- **Provisional, for the team** (also listed in the summaries): the forecast unit is the whole city, one series per hazard (plan Q21), and how the density and the probability become a risk level (plan Q22). `run_forecast.py` uses a stand-in rule, in `risk_level` only: high when the probability is at least 0.5 and the barangay's density is at least half the densest's; moderate when the probability is at least 0.5 and the density at least 0.2 of the densest, or the probability at least 0.25 and the density at least half; else low.
- **A forecast run** (`run_forecast.py`): the LSTM's probability for the 14 days ending on `--as-of` (default: the weather file's last day; replaying the records is the thesis's "simulated live feed"), times the KDE's density per barangay, by the rule above. Writes `forecast_run.json` (probabilities and counts per level) and `build/forecast_insert.sql`, one statement that adds the run for every barangay in the database (paste it in the Supabase SQL editor). Rows are marked `is_simulated` with model version `lstm-kde-v1 (sample data, provisional levels)`, which D8 and the Alerts tab show. The run of 2026-10-03 (window ending 31 Dec 2025 on the sample data: fire 66%, flood 11%, storm surge 0%) is loaded on the hosted project.
- **Two things the sample already shows** (they come from the method, not the made-up numbers): (1) the 14-day window holds only past weather, so rain that falls during the next 72 hours is not in the input; a flood after a dry spell cannot be foreseen from it. The model can learn the season, an approaching typhoon's first days, and recent incidents. Whether the last day of the window should carry PAGASA's own forecast is a question for the team. (2) With three years of records, a chronological 15% validation part falls in one season (Feb to Jul 2025 here, few floods), which makes early stopping on it shaky; more years, or a validation part chosen per season, would help.
- **LSTM** (`train_lstm.py`, the thesis parameters): two stacked LSTM layers of 64 and 32 units with dropout 0.2 after each, a sigmoid output, binary cross-entropy weighted by the class weights from the preparation, Adam at 0.001, batch 32, up to 100 epochs, early stopping after 10 epochs without a better validation loss (best weights kept), a fixed seed so a rerun gives the same model. One model per hazard. Writes `lstm_metrics.json` (epochs, the LSTM's accuracy, precision, recall, F1, RMSE, and confusion matrix on validation and test, next to the three baselines) and `build/lstm_<hazard>.keras` and `.tflite` (git-ignored).
- **The phone copy:** the TFLite file is made from a copy of the same network with the 14 steps unrolled and one window at a time, so it needs only TFLite's built-in operations (about 195 KB; no TensorFlow "select ops", which would add megabytes to the app). The script checks it against Keras on the test windows (largest difference about 0.0000005). Whether the phone runs it at all is plan Q2.
- **On the sample data the LSTM does not beat the baselines** (test F1 0.27 for floods against 0.36 for "an incident in the last 3 days"). That is expected from made-up data and from the past-only window described above; it is not a result either way. Rerun on the real records before reading anything into it.
