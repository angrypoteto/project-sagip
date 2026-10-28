# Objective 2: preprocessing log and first results on public records (2026-10-28)

> Objective 2: "To achieve a minimum classification accuracy of 80% in generating 72-hour disaster risk heatmaps by pre-processing the historical PAGASA weather records and MDRRMD incident datasets — cleaning, geocoding, and time-aligning them, and documenting the number of records retained, corrected, and removed at each step — then training a Long Short-Term Memory (LSTM) Neural Network on the prepared data."

**Read this first.** PAGASA's records and MDRRMD's incident records have not arrived. Everything below runs on the closest **public** records: real, with a link for each, but incomplete. The pipeline is the thesis's, end to end. The numbers show what these records can support. They are **not** the Chapter 4 result for Manila. That comes when MDRRMD's records are put through the same scripts.

Nothing here is loaded into the database or shown in the apps (Joshua, 2026-10-28: "don't put it yet on the systems").

## 1. The records used

| Thesis input | Stand-in used | Where |
|---|---|---|
| PAGASA daily rainfall | **GSMaP Gauge v6** (JAXA): satellite rainfall corrected with rain gauges, 0.1° cells, the four cells over Manila weighted by the city's area in each. Open data, credit "GSMaP (JAXA)" | `ml/forecast/data_prep/fetch_gsmap.py` → `data/manila_gsmap_daily.csv` |
| PAGASA wettest hour, wind | ERA5 reanalysis through Open-Meteo (CC BY 4.0); GSMaP's hourly series starts only in 2025 | `data_prep/fetch_weather.py` → `data/manila_weather_daily.csv` |
| PAGASA typhoon signals | 23 days a signal was up over Metro Manila, from news reports (incomplete) | `data/manila_signals.csv` |
| PAGASA storm surge | none found for any day | (0 on every day) |
| MDRRMD fire incidents | 131 fire reports, Asia Fire News archive (Tokyo University of Science) | `data/manila_fire_news.csv` |
| MDRRMD flood incidents | 56 flooded corners from MMDA lists reprinted in the news (2021 to 2026), plus 19 flood days found on 2026-10-28 that name City of Manila streets (2012 to 2024; from search summaries, **not yet checked**) | `data/manila_flood_news.csv`, `data/manila_flood_days.csv` |
| Barangay hazard (for the heatmap) | UP NOAH flood (5, 25, 100-year rain) and storm surge (SSA 1 to 4) maps for Metro Manila, ODbL, credit "UP NOAH" | `data_prep/noah_barangays.py` → `data/noah_barangay_hazard.csv` |

## 2. Records retained, corrected, and removed at each step

From `ml/forecast/data_prep/prep_summary_real.json` (`data_prep/prepare_real.py`). Weather period: 2012-01-01 to 2026-10-05 (5,392 days).

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

From `ml/forecast/lstm/lstm_metrics_real.json` (`lstm/train_lstm.py`). Test part, threshold 0.5:

| Hazard | Accuracy | Balanced accuracy | Precision | Recall | F1 | RMSE | "Never an incident" accuracy | Best baseline F1 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Flood | **94.2%** | 54.8% | 0.19 | 0.12 (4 of 34) | 0.15 | 0.22 | 95.8% | 0.19 (logistic regression) |
| Fire | **62.9%** | 45.4% | 0.07 | 0.24 (13 of 54) | 0.10 | 0.45 | 91.0% | 0.28 (logistic regression) |

## 4. The 72-hour heatmap, per barangay

From `ml/forecast/heatmap/heatmap_metrics_real.json` (`heatmap/evaluate_heatmap.py`). Every test day × 897 barangays. "At risk" = moderate or high by the rule of plan Q22. Truth = a placed incident in that barangay in the next 72 hours.

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

## 7. Rerun with more public records (2026-10-28, afternoon)

MDRRMD had still not replied, so Joshua asked for every public source that could stand in (section 1 was the morning's). Three were added:

| Record | Source | What it adds |
|---|---|---|
| Fires | **DSWD DROMIC** fire reports (dromic.dswd.gov.ph): every fire in Manila that affected families, 2017 to 2026, with its barangay and date in the report's title (`collect_dromic.py`, `place_fires.py`) | 190 fires; 164 placed at a barangay. About 20 a year, against about 10 a year in the news archive |
| Fires | **TXTFIRE** fire alerts (txtfire.net, a volunteer fire network in Metro Manila; `collect_txtfire.py`) | 555 confirmed fires in Manila (an alarm raised or the fire put out), 2018 to mid-2022; 219 placed at a barangay or street (streets found on OpenStreetMap and kept only inside their own district) |
| Floods | **DSWD DROMIC** monsoon and typhoon reports: 203 events searched for the City of Manila | 22 events that affected Manila, 2018 to 2026 (one, 11 Dec 2025, names its 8 barangays) |
| Typhoon signal | **NOAA IBTrACS** storm tracks, turned into an estimated PAGASA signal for every day (`storm_signal.py`) | 74 days given a signal the news did not report. The estimate matches 19 of the 23 news-reported days on the day itself |

Three versions were run, with the thesis LSTM parameters unchanged (`prepare_real.py --variant`):

- **news**: the morning's run, 2012 to 2026.
- **dromic**: DROMIC fires; DROMIC events with the news flood records; signals from news and storm tracks; 2018 to 2026.
- **dromic_txtfire**: as dromic, with TXTFIRE's fires added. Fires use only the months TXTFIRE posted alerts: Apr 2018 to Dec 2019, and Jul 2021 to Jun 2022.

### Step log of the dromic version (new rows; the weather rows are as in section 2)

| Dataset | Step | In | Retained | Corrected | Removed | What happened |
|---|---|---:|---:|---:|---:|---|
| Typhoon signals | Estimate from storm tracks | 260 | 97 signal days | 76 | 0 | 74 days added, 2 raised above the news level |
| Fire (DROMIC) | Read | 190 | 190 | 0 | 0 | |
| Fire (DROMIC) | Clean | 190 | 186 | 0 | 4 | 1 with no date anywhere, 3 reported twice |
| Fire (DROMIC) | Geocode | 186 | 186 | 0 | 0 | barangay 164, district 21, city 1; only barangay positions go to the KDE |
| Fire (DROMIC) | Time-align | 186 | 182 | 0 | 4 | 2017 left out (DROMIC posted only 4 Manila fires that year) |
| Flood (news) | Time-align | 66 | 53 | 0 | 13 | the news flood days before 2018 left out |
| Flood (DROMIC events) | Clean | 203 | 22 | 0 | 181 | Manila not in the report (139), or the report would not open (42; the 2016 and 2017 ones were Google Docs that are gone) |
| Flood (DROMIC events) | Geocode | 22 | 28 | 0 | 0 | 7 barangay records from the one report that names them; 21 city-wide events (LSTM only) |
| Flood (news + DROMIC) | Merge | 81 | 80 | 1 | 0 | one DROMIC day already in the news records |

In the dromic_txtfire version, TXTFIRE adds:
- **Clean:** 555 in, 521 kept, 34 removed (the same fire twice).
- **Time-align:** 505 kept (16 outside the covered months).
- **Merge:** 20 TXTFIRE fires matched a DROMIC fire and were counted once.

### Results on the test part

| Version | Hazard | Test days | LSTM accuracy | Balanced accuracy | Caught | Never-warn (or always-warn) accuracy | Heatmap accuracy per barangay | Heatmap balanced |
|---|---|---|---:|---:|---|---:|---:|---:|
| news | flood | 2024-07 to 2026-10 | 94.2% | 54.8% | 4 of 34 | 95.8% | 97.1% (UP NOAH) | 58.2% |
| news | fire | 2023-06 to 2025-01 | 62.9% | 45.4% | 13 of 54 | 91.0% | 56.7% (KDE) | 40.9% |
| dromic | flood | 2025-06 to 2026-10 | 86.6% | 53.9% | 6 of 42 | 91.2% | 93.2% (UP NOAH) | 57.7% |
| dromic | fire | 2025-06 to 2026-10 | 61.3% | 51.4% | 32 of 90 | 81.2% | **80.4%** (KDE) | 53.4% |
| dromic_txtfire | fire | 2022-02 to 2022-06 | 59.6% | 44.9% | 81 of 114 | 78.1% (always warn) | 38.6% (KDE) | 52.6% |

(The flood rows of dromic_txtfire equal dromic's: only the fires differ.)

### What the rerun says

1. **More records did not give the models skill.** Every version stays below the forecast that never warns (or, with TXTFIRE's dense fires, the one that always warns). Balanced accuracy stays near 50%, which is a coin toss. The dromic fire heatmap reaches 80.4% per barangay, but "nothing at risk" reaches 99.98% on the same cells, so it does not show the 80% objective is met.
2. **Floods: the rain is there, the flood records are not.**
   - Flood days are much wetter than other days (median 23.7 mm against 1.8 mm), and so are the three days before them (12 to 16 mm). So past weather does carry a warning.
   - But 8% of all days have 20 mm or more, and most of those have no recorded flood. DROMIC lists only events that displaced families, and the MMDA lists only some days.
   - The model cannot tell a wet day that flooded from one that "did not". The fix is complete flood records (MMDA or MDRRMD).
3. **Fires: weather barely drives them.**
   - Fires follow the dry season a little: DROMIC has 76 in January to April against 33 in August to October. But day to day they come from cooking, wiring, and crowding, which no weather input shows. With DROMIC's ~20 a year, a fire is in the next 72 hours on about 1 day in 5; with TXTFIRE's, on 3 days in 4.
   - Neither can be told from the weather. A city-wide 72-hour fire forecast from weather may not be achievable at all.
   - The **KDE** half (where fires happen) does fit: on the 86 placed DROMIC fires of the training part its bandwidth comes out at 300 m. Its 30 densest barangays are all in Tondo (22) and Santa Cruz (8), checked on fires up to mid-2024.
4. **Storm surge** still has no incident in any source.

### To decide (team), added

- **Q49. Typhoon signal estimate.** If PAGASA's signal records do not come, Chapter 3 can describe the feature as "PAGASA's wind signal, estimated from NOAA IBTrACS storm tracks where PAGASA's own record is missing" (`storm_signal.py`; it matches 19 of 23 known days).
- **Q50. What Objective 2 measures.** On every public record tried, an LSTM on past weather does not beat "never an incident". The thesis can do one of these:
  - (a) keep the objective and wait for MDRRMD's records;
  - (b) report the 80% heatmap accuracy honestly next to the never-warn baseline and balanced accuracy (Q23);
  - (c) for floods, let the last day of the window carry PAGASA's rainfall forecast. The team raised this earlier; the rain analysis above shows it matters.

  Fire forecasting from weather should be described as limited in Chapter 5 whichever is chosen.

## 8. Experiment: would PAGASA's rainfall forecast help? (Q50 c)

Not the thesis feature set; run only to inform the team. PAGASA's past forecasts are not available. Instead, the rain that actually fell next was given to the LSTM as a seventh feature, as if the forecast had been perfect (`prepare_real.py --variant dromic --forecast-rain-days 1|3`). Same parameters, same test part (Jun 2025 to Oct 2026). A real forecast is worse than this, so these numbers are the most a forecast could add.

| Rain forecast in the window | Flood accuracy | Flood balanced accuracy | Floods caught | Flood F1 | Fire balanced accuracy |
|---|---:|---:|---|---:|---:|
| none (dromic, section 7) | 86.6% | 53.9% | 6 of 42 | 0.16 | 51.4% |
| next 24 hours, perfect | 85.6% | 57.7% | 10 of 42 | 0.22 | 49.9% |
| next 72 hours, perfect | 85.2% | 61.7% | 14 of 42 | 0.28 | 52.2% |

"Never a flood" scores 91.2% on the same windows.

**Reading:**
- A forecast does help floods, as expected: with the next 72 hours' rain known, the model catches a third of the flood windows instead of a seventh.
- Even a perfect forecast does not lift accuracy above never warning. The flood records are still too incomplete: many wet days have no recorded flood, so warnings on them count as false.
- It does nothing for fires, as expected.
- Of the three Q50 options, (c) is worth adopting for floods only together with better flood records. On its own it does not meet the 80% objective in a meaningful way.

## How to rerun

```bash
cd ml/forecast
../../.venv/Scripts/python data_prep/fetch_gsmap.py --start 2012-01-01 --end 2026-10-26   # about 750 MB read, an hour; resumes
../../.venv/Scripts/python data_prep/noah_barangays.py      # needs UP NOAH's maps in data/noah/ (git-ignored); about 9 minutes
../../.venv/Scripts/python data_prep/prepare_real.py        # the step log and the windows (news version)
../../.venv-tf/Scripts/python lstm/train_lstm.py --prep data_prep/prep_summary_real.json --build build/real --out lstm/lstm_metrics_real.json
../../.venv-tf/Scripts/python heatmap/evaluate_heatmap.py

# Section 7 (downloads go to data/downloads/, git-ignored)
../../.venv/Scripts/python data_prep/collect_dromic.py      # DROMIC fires and weather events; about 160 MB of reports
../../.venv/Scripts/python data_prep/collect_txtfire.py     # TXTFIRE alerts
../../.venv/Scripts/python data_prep/place_fires.py         # positions; OpenStreetMap one request a second (about 8 minutes, cached)
../../.venv/Scripts/python data_prep/storm_signal.py        # needs the IBTrACS file in data/downloads/ibtracs/
for v in dromic dromic_txtfire; do
  ../../.venv/Scripts/python data_prep/prepare_real.py --variant $v
  ../../.venv-tf/Scripts/python lstm/train_lstm.py --prep data_prep/prep_summary_$v.json --build build/real/$v --out lstm/lstm_metrics_$v.json
  ../../.venv-tf/Scripts/python heatmap/evaluate_heatmap.py --variant $v
done
```
