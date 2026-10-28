# Dijkstra: the fastest route for responders (FR10)

Dijkstra's shortest-path algorithm over the Manila road graph, as the thesis sets it: a directed road graph, nodes are intersections, each edge weighted by estimated travel time, and a binary-heap priority queue. It runs inside the apps (the responder's phone and the dashboard), so routes work offline too.

| File | What it does |
|---|---|
| `dijkstra.dart` | **The algorithm.** Dijkstra's search with a binary-heap priority queue; returns the fastest path and its travel time |
| `road_graph.dart` | The directed road graph it searches: intersections, one-way and two-way road segments, travel times. Loaded from `packages/shared/assets/road_graph/manila_drive_v1.bin`, built from OpenStreetMap by `ml/road_graph/build_road_graph.py` |
| `road_router.dart` | Puts it to use: snaps the responder and the incident to the nearest intersections, runs Dijkstra, and gives the route for the map and the travel time used to suggest the nearest unit |
| `hazard_penalty.dart` | Makes roads near a confirmed flood or fire slower, so Dijkstra routes around them (provisional until MDRRMD says how each hazard slows its units) |
| `routing_log.dart` | Records how long each route took to compute (for the speed figures in Chapter 4) |

Tests: `packages/shared/test/road_graph_test.dart` checks the routes against the answers of `networkx` (a standard Python graph library) on the same graph.
