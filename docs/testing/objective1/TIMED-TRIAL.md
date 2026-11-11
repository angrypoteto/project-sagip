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

## Before you start

- Set the board as the card's **Setup** says (for example, a unit marked
  en route) before the timer starts, for both methods.
- Cards 2, 5, and 7 have **two calls**, read 30 seconds apart. Time both
  assignments, and note whether the more urgent incident got a unit first.
- Run card 1 at the time of day it names if you can; S.A.G.I.P.'s road
  times use road speeds, not live traffic, so traffic shows up only in the
  dispatcher's own choice in the current way.

## The current way (baseline)

1. The caller "calls" and reads the card. The dispatcher writes down the
   details on paper or in the logbook, as MDRRMD does now.
2. The dispatcher finds the place on a paper or phone map, decides which
   incident comes first when two are waiting, and picks the unit they would
   send, saying it aloud ("Send BFP-TONDO").
3. Stop the timer when the unit is named.

## With S.A.G.I.P.

1. The caller sends the scenario as an SOS from the resident phone (or the
   dashboard's simulation for the two-call cards), at or near the card's
   place, or with the location set on the map.
2. The dispatcher opens it from the Triage Queue, verifies it (callback or
   SMS check as the card allows), and presses **Assign** for the unit.
3. Stop the timer at **Assign**. Close the test incident right after (Mark as
   false report) so it is not counted anywhere.

## The scenarios (7 cards, the same for both methods)

Places are real barangays; the people and events are invented for the
trial. The situations follow common Manila emergencies (busy markets,
narrow lanes, flash floods, two fires at once). Earthquakes are left out:
they are outside the system's scope.

| # | Type | Place | What the caller says | Setup | What it tests |
|---|---|---|---|---|---|
| 1 | Fire | Barangay 287, Binondo | "Fire at a stall in the market, it is spreading to the next stalls. The street is full of people and jeepneys." | None; late afternoon if possible | Choosing the fastest unit by road |
| 2 | Fire, then fire (two calls) | Barangay 93, Tondo, then Barangay 105, Tondo | First: "Fire in the warehouse across the street." Second: "Our neighbour's house is on fire, two houses down from the chapel." | None | The second call, when the nearest unit has just been sent: the next-best unit still free |
| 3 | Fire | Barangay 560, Sampaloc | "Fire at the end of our alley. It is too narrow for a truck." | None | Routing to the nearest point a unit can reach by road |
| 4 | Flood | Barangay 863, Pandacan | "The water came up fast, it is above the knee on our street and still rising." | A confirmed flood on the main road nearby (send it first, verify it, leave it open) | Routing around a confirmed flood |
| 5 | Flood, then flood with a vulnerable resident (two calls) | Barangay 863, Pandacan, then Barangay 835, Pandacan | First: "Street flooded, knee-deep, we are fine upstairs." Second: "My mother is bedridden and on oxygen, the water is inside the house." | The second caller's profile lists a bedridden senior | The Triage Queue: the vulnerable household goes first |
| 6 | Medical | Barangay 659, Ermita | "My father is clutching his chest and can barely breathe." | None | The dispatch steps alone (no hazard, no queue) |
| 7 | Flood, then fire (two calls) | Barangay 694, Malate, then Barangay 93, Tondo | First: "Flood in our alley, we are on the second floor, safe for now." Second: "We smell gas, the tank is leaking and the stove next to it is lit." | None | Two incidents waiting; the second is more urgent |

Notes on the two-call cards:
- **Card 2:** the dispatcher sends the nearest unit to the first fire.
  Record the second assignment's time and unit; with S.A.G.I.P. the first
  unit shows as en route, so the suggestion moves to the next one.
- **Card 5:** the Triage Queue ranks the vulnerable household above the
  other SOS. Record whether it got a unit first.
- **Card 7:** the Triage Queue ranks both as SOS with no vulnerable member,
  so the earlier call is on top; the dispatcher has to judge the gas leak
  more urgent from the description. Record what they did; it is the same
  judgment in both methods.

If you want all four incident types, add the earlier structural card:
Barangay 560, Sampaloc, "Part of the wall fell, someone is pinned."

## Afterwards

For each scenario and method, read the road ETA of the unit (or units) chosen from
S.A.G.I.P. (open the incident; the suggested units show each unit's ETA by
road). Send me the tally sheet and I fill in Chapter 4 section 4.1.6.
