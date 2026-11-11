# Objective 1: the Priority Queue in a surge, and the 5-minute fire target

Joshua, 2026-11-12: keep Objective 1 as written. MDRRMD does not control
the responders' travel, and the time on scene (fire out, flood rescue)
depends on the situation, so Objective 1 is measured on the parts the system
changes: the **dispatch** wait (report to unit sent) and the **routing**
(the unit chosen and its road travel time).

## A. The Priority Queue in a typhoon surge

**Run it again:** `cd packages/shared`, then
`SAGIP_EVAL=1 flutter test test/objective1_queue_simulation_test.dart`.
Results: `queue_simulation_summary.json`, `queue_simulation.csv`.

**How:** a 3-hour surge, with reports coming in at random at 12, 16, 20, or
30 an hour, and 10 units (as on the hosted project). Each time a unit is
free it is sent to the next waiting incident, chosen two ways from the same
surge:
- **First come, first served:** the oldest report first, as with a hotline
  logbook.
- **Triage Queue:** the first incident in `PriorityRules.order`, the real
  ranking the dashboard uses (A3 weights as seeded: SOS 50, cluster 40,
  vulnerable 30, waiting 2 a minute up to 30, mock location -20).

**Real:** the ranking code and the units' road travel times (Dijkstra,
`docs/testing/dijkstra/suggestions.csv`). **Assumed:** one SOS household in
seven vulnerable (as the NFR7 surge test), one report in five a crowd
cluster, one in 200 with a mock location; a unit busy for twice its drive
plus 20 to 60 minutes on scene. 200 surges per rate.

**Mean wait from the report to a unit being sent (minutes):**

| Reports an hour | Vulnerable SOS: first come | Vulnerable SOS: Triage Queue | Reduction | All SOS: first come | All SOS: Triage Queue | Crowd clusters: first come | Crowd clusters: Triage Queue |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 12 (units just keep up) | 8.96 | 2.42 | **73.0%** | 8.18 | 6.37 | 8.19 | 15.86 |
| 16 | 24.89 | 4.07 | **83.7%** | 24.79 | 17.09 | 24.54 | 56.50 |
| 20 | 50.45 | 4.78 | **90.5%** | 49.49 | 32.67 | 48.23 | 113.19 |
| 30 (units far behind) | 115.05 | 6.05 | **94.7%** | 115.12 | 82.89 | 114.34 | 244.02 |

("All SOS" is the vulnerable and other SOS together, weighted by count.)

**What it shows:**
- The queue sends a unit to a vulnerable household's SOS in a mean of 2 to
  6 minutes however bad the surge, against 9 to 115 minutes first come,
  first served: **73% to 95% less**.
- SOS as a whole wait 22% to 34% less, because single-person rescues rank
  above crowd clusters.
- The cost is the crowd clusters, which wait about twice as long. They are
  hazard reports, often of an area rather than a person to rescue, so this
  follows the ranking MDRRMD's SOP is expected to confirm.
- The average over everyone does not change (8.2, 24.8, 49.2, 115 minutes
  either way): the same units clear the same work. The queue changes **who
  waits**, not how much waiting there is in total.

## B. The 5-minute fire target (routing)

A fire unit is expected on scene within 5 minutes (Joshua, 2026-11-12;
BFP-NCR has stated a 5-minute target for Metro Manila. **Cite the BFP
document** in Chapter 4). From the Dijkstra test (897 barangay centers as
incidents, all ten units at their stations, `docs/testing/dijkstra/`):

| First unit sent | Barangays reached within 5 minutes by road |
|---|---:|
| The fastest by road (Dijkstra) | **643 of 897 (71.7%)** |
| The nearest on the map (straight line) | 609 of 897 (67.9%) |

Dijkstra's choice brings **34 more barangays** within 5 minutes, and is
never slower. With a confirmed fire on the usual route, driving through it
reached the incident within 5 minutes in none of the 100 test cases; the
route around it did in 7 (12 were within 5 minutes with no fire). The
travel times use the road graph's speeds, not traffic, and only the ten
units loaded on the system, so the shares are for comparison between the
two methods, not a forecast of real arrival times.
