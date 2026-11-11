# Objective 1 timed trial: dispatch the current way and with S.A.G.I.P.

*Objective 1: to reduce emergency dispatch and routing time for MDRRMD field
responders by at least 20% through Dijkstra's Shortest Path Algorithm and an
automated priority queuing system.*

MDRRMD's records do not keep when a call came in, when a unit was sent, or how
long it drove (they record a fire's own stages only), so the baseline comes
from this trial: the **same scenarios**, handled once the current way and
once with S.A.G.I.P., timed the same way.

**Reduction = (T_current − T_with_system) / T_current × 100**, per measure,
using the medians. Target: 20% or more.

## What is measured

| Measure | Starts | Ends |
|---|---|---|
| **Dispatch time** | The caller starts reading the scenario (the "call" comes in) | The dispatcher names the unit to send (current way) or presses **Assign** (S.A.G.I.P.) |
| **Unit's road travel time** | | Read afterwards for the unit chosen, from S.A.G.I.P.'s road ETA (Dijkstra), for both methods, so the two are measured the same way |

The dispatch time covers taking the call, verifying it, deciding which
incident comes first, and choosing the unit: the part MDRRMD controls.

## People and roles

| Role | Who |
|---|---|
| **Dispatcher** | An MDRRMD dispatcher (best) or a team member acting as one. Use **different people** for the two methods, or the same person with the current way **first** |
| **Caller** | A team member who reads the scenario card aloud, by phone or in person, answering only what is on the card |
| **Timekeeper** | A team member with a stopwatch who fills in `timed_trial_tally.csv` |

## The current way (baseline)

1. The caller "calls" and reads the card. The dispatcher writes down the
   details on paper or in the logbook, as MDRRMD does now.
2. The dispatcher finds the place on a paper or phone map, decides which
   incident comes first when two are waiting (scenarios 5 and 6), and picks
   the unit they would send, saying it aloud ("Send BFP-TONDO").
3. Stop the timer when the unit is named.

## With S.A.G.I.P.

1. The caller sends the scenario as an SOS from the resident phone (or the
   dashboard's simulation for scenarios 5 and 6), standing at or near the
   scenario's place, or with the location set on the map.
2. The dispatcher opens it from the Triage Queue, verifies it (callback or
   SMS check as the card allows), and presses **Assign** for the unit.
3. Stop the timer at **Assign**. Close the test incident right after (Mark as
   false report) so it is not counted anywhere.

## The scenarios (6 cards, the same for both methods)

Places are real barangays; the people and events are invented for the trial.

| # | Type | Place | What the caller says | Notes |
|---|---|---|---|---|
| 1 | Flood | Barangay 105, Tondo | "Water is waist-deep inside our house. Three of us, one is a senior." | Vulnerable household |
| 2 | Fire | Barangay 287, Binondo | "Smoke from the house next to ours, it is spreading to the roof." | |
| 3 | Medical | Barangay 659, Ermita | "My father collapsed and is not answering." | |
| 4 | Structural | Barangay 560, Sampaloc | "Part of the wall fell, someone is pinned." | |
| 5 | Flood + medical (two calls 30 s apart) | Barangay 863, Pandacan, then Barangay 835, Pandacan | First: "Street flooded, knee-deep." Second: "My wife is in labour and the street is flooded." | Who goes first? The second is more urgent |
| 6 | Fire + flood (two calls 30 s apart) | Barangay 93, Tondo, then Barangay 694, Malate | First: "Fire in the warehouse across the street." Second: "Flood in our alley, we are on the second floor, safe for now." | The first is more urgent |

For scenarios 5 and 6, record the time to the **first** assignment and
whether the more urgent incident was sent first.

## Afterwards

For each scenario and method, read the road ETA of the unit chosen from
S.A.G.I.P. (open the incident; the suggested units show each unit's ETA by
road). Send me the tally sheet and I fill in Chapter 4 section 4.1.6.
