# Objective 2: preprocessing log and first results on public records (2026-10-28)

> Objective 2: "To achieve a minimum classification accuracy of 80% in generating 72-hour disaster risk heatmaps by pre-processing the historical PAGASA weather records and MDRRMD incident datasets — cleaning, geocoding, and time-aligning them, and documenting the number of records retained, corrected, and removed at each step — then training a Long Short-Term Memory (LSTM) Neural Network on the prepared data."

**Read this first.** PAGASA's records and MDRRMD's incident records have not arrived. Everything below runs on the closest **public** records: real, with a link for each, but incomplete. The pipeline is the thesis's, end to end. The numbers show what these records can support. They are **not** the Chapter 4 result for Manila. That comes when MDRRMD's records are put through the same scripts.

Nothing here is loaded into the database or shown in the apps (Joshua, 2026-10-28: "don't put it yet on the systems").

## 1. The records used

| Thesis input | Stand-in used | Where |
|---|---|---|
| PAGASA daily rainfall | **GSMaP Gauge v6** (JAXA): satellite rainfall corrected with rain gauges, 0.1° cells, the four cells over Manila weighted by the city's area in each. Open data, credit "GSMaP (JAXA)" | `ml/forecast/fetch_gsmap.py` → `data/manila_gsmap_daily.csv` |
| PAGASA wettest hour, wind | ERA5 reanalysis through Open-Meteo (CC BY 4.0); GSMaP's hourly series starts only in 2025 | `fetch_weather.py` → `data/manila_weather_daily.csv` |
| PAGASA typhoon signals | 23 days a signal was up over Metro Manila, from news reports (incomplete) | `data/manila_signals.csv` |
| PAGASA storm surge | none found for any day | (0 on every day) |
| MDRRMD fire incidents | 131 fire reports, Asia Fire News archive (Tokyo University of Science) | `data/manila_fire_news.csv` |
| MDRRMD flood incidents | 56 flooded corners from MMDA lists reprinted in the news (2021 to 2026), plus 19 flood days found on 2026-10-28 that name City of Manila streets (2012 to 2024; from search summaries, **not yet checked**) | `data/manila_flood_news.csv`, `data/manila_flood_days.csv` |
| Barangay hazard (for the heatmap) | UP NOAH flood (5, 25, 100-year rain) and storm surge (SSA 1 to 4) maps for Metro Manila, ODbL, credit "UP NOAH" | `noah_barangays.py` → `data/noah_barangay_hazard.csv` |

## 2. Records retained, corrected, and removed at each step

From `ml/forecast/prep_summary_real.json` (`prepare_real.py`). Weather period: 2012-01-01 to 2026-10-05 (5,392 days).

| Dataset | Step | In | Retained | Corrected | Removed | What happened |
|---|---|---:|---:|---:|---:|---|
| GSMaP rainfall | Read | 5,413 | 5,333 | 0 | 80 | JAXA has no file for 80 days |
| GSMaP rainfall | Clean | 5,333 | 5,318 | 0 | 15 | a cell with no reading (no-data value) |
| GSMaP rainfall | Time-align | 5,318 | 5,318 | 0 | 0 | GSMaP's day is 00:00 to 23:59 UTC = 08:00 to 07:59 Manila time (PAGASA's 8 AM rainfall day); kept as the Manila date it starts on |
| GSMaP rainfall | Keep the period | 5,318 | 5,300 | 0 | 18 | days after 2026-10-05 |
| ERA5 | Read and clean | 5,392 | 5,392 | 0 | 0 | already in Manila days |
| Typhoon signals | Read | 23 | 23 | 0 | 0 | every other day is signal 0 |
| Daily features | Merge and correct | 5,392 | 5,392 | 1,175 | 0 | 92 days without GSMaP filled with ERA5's total; 1,083 days where ERA5's wettest hour was above GSMaP's whole day, lowered to the day's total |
| Fire | Read | 131 | 131 | 0 | 0 | |
| Fire | Clean | 131 | 130 | 0 | 1 | one fire reported twice (same day, within 300 m) |
| Fire | Geocode | 130 | 130 | 0 | 0 | placed by barangay 23, by street 43, district only 64; each matched to its barangay boundary. District-only points count for the LSTM, not the KDE |
| Fire | Time-align | 130 | 130 | 0 | 0 | kept only the stretches the archive covers: 2012-02 to 2016-12 and 2019-01 to 2025-01 (no reports for 2017 and 2018) |
| Flood | Read | 75 | 75 | 0 | 0 | 56 corners + 19 flood days |
| Flood | Clean | 75 | 67 | 0 | 8 | the same corner area twice on one day (within 300 m) |
| Flood | Geocode | 67 | 66 | 0 | 1 | 47 corners placed where the two streets meet (OpenStreetMap) and matched to a barangay; 1 fell outside the city; 19 days have no single point (LSTM only) |
| Flood | Time-align | 66 | 66 | 0 | 0 | |
| Storm surge | Read | 0 | 0 | 0 | 0 | no incident found: the LSTM cannot be trained for storm surge |

What the LSTM trains on (14-day windows, label = at least one incident in the next 72 hours, chronological 70/15/15 split):

| Hazard | Incidents (days) | Train windows (positive) | Validation (positive) | Test (positive) | Test period |
|---|---|---|---|---|---|
| Fire | 130 (129) | 2,786 (243) | 595 (53) | 598 (54) | 2023-06-11 to 2025-01-28 |
| Flood | 66 (36) | 3,759 (44) | 803 (9) | 807 (34) | 2024-07-18 to 2026-10-02 |

## 3. The LSTM (thesis architecture and parameters, unchanged)

From `ml/forecast/lstm_metrics_real.json` (`train_lstm.py`). Test part, threshold 0.5:

| Hazard | Accuracy | Balanced accuracy | Precision | Recall | F1 | RMSE | "Never an incident" accuracy | Best baseline F1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Flood | **94.2%** | 54.8% | 0.19 | 0.12 (4 of 34) | 0.15 | 0.22 | 95.8% | 0.19 (logistic regression) |
| Fire | **62.9%** | 45.4% | 0.07 | 0.24 (13 of 54) | 0.10 | 0.45 | 91.0% | 0.28 (logistic regression) |

## 4. The 72-hour heatmap, per barangay

From `ml/forecast/heatmap_metrics_real.json` (`evaluate_heatmap.py`). Every test day × 897 barangays. "At risk" = moderate or high by the rule of plan Q22. Truth = a placed incident in that barangay in the next 72 hours.

| Hazard | Spatial layer | Accuracy | Balanced accuracy | Recall | Precision | "Nothing at risk" accuracy |
|---|---|---:|---:|---:|---:|---:|
| Flood | UP NOAH flood zones (25-year rain) | **97.1%** | 58.2% | 0.19 (22 of 114) | 0.001 | 99.98% |
| Fire | KDE of placed fires (bandwidth 500 m) | **56.7%** | 40.9% | 0.25 (9 of 36) | 0.00004 | 99.99% |

The flood KDE could not be fitted: only 1 placed flood corner falls in the training part (the corner lists start in 2021), and 5-fold cross-validation needs 10. UP NOAH's map stood in for it.

## 5. What this says about Objective 2

1. **The preprocessing half is done and documented.** Every step (cleaning, geocoding, time-aligning) logs records in, retained, corrected, and removed (section 2). The same script will take MDRRMD's records.
2. **The 80% figure is met for floods and missed for fires, but neither number shows skill.** Flood accuracy is 94% for the LSTM and 97% for the heatmap. A forecast that never warns scores higher (96% and 99.98%), because flood days are rare. Fire accuracy is 63% and 57%, below 80%, and the fire warnings are right less often than chance. Plan risk 14 and Q23 predicted this: with rare incidents, accuracy alone rewards silence.
3. **Why the models have no skill on these records:**
   - **Incidents are what made the news, not what happened.** BFP counted 212 structural fires in Manila in 2021; the archive has 8. A fire model trained on news learns when fires were reported.
   - **Flood days are uneven over time.** 2012 to 2020 has only the big events a search turned up; 2025 and 2026 have many small ones from daily MMDA lists. The test years look different from the training years.
   - **The window holds only past weather** (thesis design): rain that falls during the next 72 hours is not in the input, so a flood after a dry spell cannot be foreseen. Whether the last day should carry PAGASA's own rainfall forecast is a question for the team (ml/README).
4. **What would meet the objective properly:**
   - MDRRMD's incident records (Table 3.1 items 1 and 6). This is the one thing that matters most.
   - PAGASA's daily records for Port Area or Science Garden, or keep GSMaP and say so in Chapter 3.
   - Report accuracy **with** balanced accuracy, recall, precision, and the "never an incident" baseline, as Q23 suggests. The panel will ask why 94% is not good when 96% comes free.

## 6. To decide (team)

- **Q47. GSMaP in place of PAGASA rainfall.** GSMaP fits Manila's known storm days far better than ERA5 did (7 Aug 2012 southwest monsoon: GSMaP 208 mm, ERA5 26 mm). If PAGASA's station records do not come, Chapter 3 should name GSMaP (JAXA) as the rainfall source.
- **Q48. UP NOAH hazard maps in the heatmap.** The thesis's spatial half is the KDE of past incidents. Storm surge has no incidents and floods have too few placed ones before 2021, so the heatmap has nothing to spread. UP NOAH's zones fill that gap. Using them is a method change: Chapter 3 would say "KDE of past incidents where there are enough; UP NOAH hazard zones otherwise".
- **Q23 (open).** Which numbers Chapter 4 reports beside accuracy.

## How to rerun

```bash
cd ml/forecast
../../.venv/Scripts/python fetch_gsmap.py --start 2012-01-01 --end 2026-10-26   # about 750 MB read, an hour; resumes
../../.venv/Scripts/python noah_barangays.py      # needs UP NOAH's maps in data/noah/ (git-ignored); about 9 minutes
../../.venv/Scripts/python prepare_real.py        # the step log and the windows
../../.venv-tf/Scripts/python train_lstm.py --prep prep_summary_real.json --build build/real --out lstm_metrics_real.json
../../.venv-tf/Scripts/python evaluate_heatmap.py
```
