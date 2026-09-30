# ml/

Data preparation and model training for S.A.G.I.P. (plan sections 10.2 to 10.5). Nothing here runs in the apps; the apps use what these scripts export.

| Folder | What it makes | Used by |
|---|---|---|
| `road_graph/` | The directed Manila road graph for Dijkstra (`packages/shared/assets/road_graph/manila_drive_v1.bin`) and the networkx reference answers for its test | `RoadGraph`, `RoadRouter`, and `RoadNetworkSuggester` in `packages/shared` |

Still to come: the TF-IDF incident type classifier (10.4) and the LSTM + KDE forecast (10.5), once the Data role delivers the MDRRMD records.

## Setup

Python 3.12 or newer. Use a virtual environment in the repo root (git-ignored):

```bash
python -m venv .venv
.venv/Scripts/python -m pip install -r ml/requirements-road-graph.txt   # Windows
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
