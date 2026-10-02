# ml/

Data preparation and model training for S.A.G.I.P. (plan sections 10.2 to 10.5). Nothing here runs in the apps; the apps and the database use what these scripts export.

| Folder | What it makes | Used by |
|---|---|---|
| `road_graph/` | The directed Manila road graph for Dijkstra (`packages/shared/assets/road_graph/manila_drive_v1.bin`) and the networkx reference answers for its test | `RoadGraph`, `RoadRouter`, and `RoadNetworkSuggester` in `packages/shared` |
| `classifier/` | The incident type classifier for crowd reports (FR12): `packages/shared/assets/classifier/incident_classifier_v1.json`, the reference answers for its tests, `metrics.json`, and the SQL that loads the model into the database | `private.classify_report` in the database (the trigger on `crowd_report`) and `IncidentClassifier` in `packages/shared` |

Still to come: the LSTM + KDE forecast (10.5), once the Data role delivers the MDRRMD records.

## Setup

Python 3.12 or newer. Use a virtual environment in the repo root (git-ignored):

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r ml/requirements-road-graph.txt   # Windows
.venv/Scripts/python -m pip install -r ml/requirements-classifier.txt   # only for the classifier
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
