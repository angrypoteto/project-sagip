# Objective 1 timed trial: results (14 November 2026, run 2)

**Dispatcher:** an MDRRMD dispatcher. **Caller:** a proponent (read each card aloud).
**Timekeeping:** one clock for both methods. Start = the card posted to the
caller; stop = the caller's "done" message, sent the moment the dispatcher
said he had decided (current way) or pressed Assign (S.A.G.I.P.). The same
relay delay is in both methods. Raw stamps: `trial_timelog.csv`. Run 1 (03:38
to 03:44) was set aside at the team's request: `trial_timelog_void_run1.csv`.

**Current way:** Google Maps and the unit list (10 units). **S.A.G.I.P.:**
simulated SOS on the live board, verified and assigned from the Triage Queue.
Order: cards 1 to 4 current way first, cards 5 to 7 S.A.G.I.P. first.

| Card | Scenario | Current way (s) | S.A.G.I.P. (s) | Reduction | S.A.G.I.P., server: SOS received to last Assign (s) |
|---:|---|---:|---:|---:|---:|
| 1 | Market fire, Binondo | 44.4 | 20.0 | 55.0% | 9.1 |
| 2 | Two fires, Tondo | 58.6 | 26.3 | 55.1% | 16.1 |
| 3 | Fire in a narrow alley, Sampaloc | 119.6 | 21.5 | 82.1% | 13.7 |
| 4 | Flash flood with a confirmed flood nearby, Pandacan | 138.0 | 18.0 | 87.0% | 11.2 |
| 5 | Flood, then a bedridden senior, Pandacan | 76.5 | 41.3 | 46.1% | 26.4 |
| 6 | Heart attack, Ermita | 73.2 | 25.2 | 65.6% | 10.5 |
| 7 | Flood, then a gas leak, Malate and Tondo | 111.3 | 38.1 | 65.7% | 22.1 |
| **Median** | | **76.5** | **25.2** | **67.1%** | 13.7 |
| Mean | | 88.8 | 27.2 | 69.4% | 15.6 |

The dispatch time fell by 67.1% (median), above the 20% target, and
S.A.G.I.P. was faster on every card (46% to 87%).

**Observations**
- Card 5: with S.A.G.I.P. the vulnerable household (Barangay 835) got a unit
  first, as the Triage Queue ranked it.
- Card 7: with S.A.G.I.P. the earlier flood call got a unit before the gas
  leak; both SOS had the same priority (no vulnerable member), as the card
  expected. The type of emergency is not in the ranking yet.
- Card 6: a fire truck (BFP-PACO) was assigned to a heart attack; the
  incident type was not set, so the ambulance was not suggested first.

**Limits:** one dispatcher, one round per card; the SOS were simulated on the
dashboard (no phone or SMS step); the current way used Google Maps, not
MDRRMD's paper map; the times include the caller's relay of "done" (same for
both methods).
