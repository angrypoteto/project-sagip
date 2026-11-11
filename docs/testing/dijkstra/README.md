# Dijkstra test results (Objective 1, FR3, FR10)

Run on 2026-11-11 by `packages/shared/test/dijkstra_evaluation_test.dart`
on the real Manila road graph, plus the timing the apps logged on the hosted
project (`routing_run`). Every figure below is in a file in this folder.

| File | What it holds |
|---|---|
| `summary.json` | Every figure in this page, as the test computed it |
| `suggestions.csv` | One row per barangay (897): the unit Dijkstra suggests, its ETA, the unit nearest in a straight line, and that unit's ETA by road |
| `routes.csv` | One row per barangay: the route from the suggested unit (minutes, road km, straight km, turns, compute time) |
| `hazards.csv` | 100 flood and 100 fire cases: the time through the hazard, the time around it, and whether the route avoids it |
| `field_timing.csv` | Execution time logged by the real apps (phones and dashboard), Oct 3 to Nov 10 |

**Inputs (all public):** the OpenStreetMap road graph of Manila (9,296
intersections, 23,716 one-way road segments, built 2026-09-30), the 897
barangay centers (PSA) as incident points, and the ten unit stations loaded
on the hosted project (OpenStreetMap). No incident, resident, or MDRRMD record
was used.

**To run again:** `cd packages/shared`, then
`SAGIP_EVAL=1 flutter test test/dijkstra_evaluation_test.dart`.

## Where the system uses Dijkstra

| # | Where | What it does | Tested in |
|---|---|---|---|
| 1 | Dashboard, incident drawer: suggested units | One search from the incident over the reversed road graph gives every Available unit's travel time; the units are ranked by it | Test 2 |
| 2 | Dashboard, on dispatch | The route from the unit to the incident, drawn on the map and sent with the assignment | Test 3 |
| 3 | Responder's phone, navigation | The same route on the phone (works offline), worked out again as the unit moves | Tests 3 and 4 |
| 4 | Both, around confirmed floods and fires | Roads near a confirmed flood (150 m, 4 times slower) or fire (100 m, 20 times slower) cost more, so the route goes around them | Test 5 |
| 5 | Resident's phone | Where the unit is likely driving (Track responder), and the walk to a safe place | Same router as 2 and 3; not tested apart |

## Test 1: Does it find the true fastest route?

Checked against `networkx`, a standard Python graph library, on the same graph.

| Check | Result |
|---|---|
| 50 random origin and destination pairs | **50 of 50** equal; largest difference 0.000 s |
| One reverse search to 8 unit positions | **8 of 8** equal |

## Test 2: Unit suggestions (FR3)

For each of the 897 barangay centers as an incident, with all ten units
Available at their stations: the unit Dijkstra puts first, against the unit
nearest in a straight line (what a dispatcher would pick from a map).

| Measure | Result |
|---|---|
| Incident points where every unit got a road ETA | 897 of 897 |
| Same first unit as the straight-line pick | 646 (72.0%) |
| **A different, faster unit** | **250 (27.9%)** |
| Time saved in those 250 cases | median 0.48 min (28 s), mean 0.86 min, largest 4.44 min |
| Travel time saved in those 250 cases | median 8.2%, mean 14.7%, largest 58.5% |
| Travel time saved over all 897 points | mean 4.1% |
| Never slower than the straight-line pick | yes, in all 897 |
| Execution time on the PC | median 1.70 ms, 95th percentile 3.14 ms, largest 64.5 ms |

In one case in four, the unit closest on the map is not the one that
arrives first: a river, a one-way street, or a missing bridge puts it
behind another station. Dijkstra picks the faster one every time.

## Test 3: The route on dispatch and in navigation (FR10)

From the suggested unit's station to each of the 897 incident points.

| Measure | Result |
|---|---|
| Routes whose road segments join up end to end | 897 of 897 |
| Routes that start at the unit and end at the incident | 897 of 897 |
| Route ETA equal to the ETA shown in the suggestion | 897 of 897 |
| Travel time | median 3.89 min, mean 4.09 min, 95th percentile 7.32 min, longest 11.09 min |
| Road distance over straight distance | median 1.56, mean 1.70 |
| Execution time on the PC | median 0.17 ms, 95th percentile 0.67 ms, largest 3.83 ms |

## Test 4: Rerouting while the responder drives

From every fifth intersection along 100 random routes (924 reroutes). The
time left must equal the full time minus the time already driven.

| Measure | Result |
|---|---|
| Reroutes where the time left is consistent | 924 of 924 |
| Execution time on the PC | median 0.26 ms, 95th percentile 1.50 ms |

## Test 5: Routing around confirmed floods and fires

A hazard is placed in the middle of the fastest route (routes of 1.5 km or
more, hazard at least 400 m from either end), then the route is worked out again.

| Measure | Flood (150 m, 4 times slower) | Fire (100 m, 20 times slower) |
|---|---|---|
| Cases | 100 | 100 |
| New route avoids the hazard | **86** | **99** |
| Minutes saved against driving through | median 1.30, largest 2.65 | median 6.74, largest 13.28 |
| Extra distance | median 0.21 km | median 0.22 km |
| Execution time with the penalty | median 2.64 ms, 95th percentile 10.7 ms | median 2.22 ms, 95th percentile 7.9 ms |

In the 14 flood cases that keep the route, going through slowly is still
faster than any way around. This is intended: a flooded street can still be
driven, a fire street cannot. The slow-down factors are provisional until
MDRRMD says how each hazard slows its units.

## Test 6: Execution time in the field (`routing_run`, hosted project)

Every route and suggestion the apps made, timed by the apps themselves from
the routing request to the finished path (thesis: T_execution = T_end − T_start).

| Where | Runs | Median | 95th percentile | Largest | At or under 100 ms |
|---|---:|---:|---:|---:|---:|
| Route on the responder's phone (Android, 5 accounts, Oct 3 to 22) | 260 | 8.89 ms | 53.01 ms | 139.67 ms | 256 (98.5%) |
| Route on the dashboard (web) | 40 | 1.35 ms | 2.53 ms | 3.70 ms | 40 (100%) |
| Unit suggestions on the dashboard (web, 8.8 units on average) | 196 | 6.30 ms | 28.20 ms | 134.50 ms | 195 (99.5%) |

A full search over the whole graph, with no early stop, takes a median of
1.46 ms on the PC. Even the slowest phone run (0.14 s) is far below the time
a dispatcher needs to read the suggestion.

## What this does and does not show for Objective 1

Objective 1 asks for at least 20% less dispatch and routing time than
MDRRMD's current way. **The before figure is still missing**: MDRRMD's
dispatch times are letter item C, not received yet. These results show:

- Dijkstra gives the true fastest route (Test 1) in a few milliseconds on
  the dashboard and under 0.1 s on almost every phone run (Test 6).
- Against picking the nearest unit by map distance, it picks a faster unit
  in 27.9% of incident points, saving 14.7% of travel time in those cases on
  average (Test 2). Over all points the saving is 4.1%. This is a road-model
  estimate, not a measured drive.
- On the system's own test incidents (59 between Oct 12 and Nov 10, made by
  the team), the median time from receipt to assignment was **48.9 s**
  (36 assigned). Compare it with MDRRMD's figure when it arrives.

**Limits:** the road speeds per road class are provisional (no traffic), the
units start at their stations, and the barangay centers stand in for
incidents. Real drives may differ.
