# Objective 3, simulation B: the field trial's conditions in simulated time

Joshua, 2026-11-12: "can you simulate it" (the Objective 3 field trial).

Simulation A (`README.md`) shows the offline logic delivers every SOS a tier
can carry, with perfect radios. Simulation B adds **time and failure**: the
same four conditions as the field trial (Table 4.9b), 500 presses each, and
a press counts only if the SOS reaches the server **within 3 minutes**.

To run it again: `cd packages/shared`, then
`SAGIP_EVAL=1 flutter test test/objective3_timed_simulation_test.dart`.
Results: `simulation_b_summary.json` (every figure) and
`simulation_b_rates.csv` (one row per setting and condition).

## What is real and what is assumed

**Real (the app's own code, build 31 behaviour):** the phone's offline steps
(`SyncEngine`: no data wait when the phone knows it is offline, the
Bluetooth advert at once, a failed text tried again after 10 s) and the
nearby phone's relay (`RelayNode`: hear, upload, try again). Time runs on a
fake clock, so the app's own timers fire as they would on a phone.

**Assumed, and varied:**

| Setting | Observed value | Where it comes from |
|---|---|---|
| A text fails at the phone | 0% | The 3 real SMS all went |
| Time from a sent text to the gateway | 0.5 to 30 s | The 3 real SMS took 0.5, 15.0, and 26.4 s |
| Chance per second the nearby phone (5 m) hears the advert | 3% | Gives a median of about 23 s, as the 8 real relays (median 23.8 s) |
| The same at 15 to 20 m | 1% (a guess) | **Not measured**; varied below |
| The nearby phone's scan has stopped at the press | 0% | Build 31 restarts it within 10 minutes; varied below |
| The nearby phone's upload | 0 to 2 s | The real internet SOS (median 0.3 s) |

## Results (S_rate within 3 minutes, 500 presses per cell)

| Setting | F1 SMS only | F2 Bluetooth 5 m | F3 Bluetooth 15–20 m | F4 text fails, Bluetooth |
|---|---:|---:|---:|---:|
| **Observed** | **100%** | **99.8%** | 83.2% | **99.2%** |
| Far phone hears as well as near (3%/s) | 100% | 99.6% | 99.4% | 99.4% |
| Far phone hears 2%/s | 100% | 99.2% | 97.8% | 99.2% |
| Far phone hears 0.5%/s | 100% | 99.8% | 56.2% | 100% |
| Texts fail 25% | 100% | 99.6% | 80.6% | 99.4% |
| Texts fail 50% | 100% | 99.4% | 83.0% | 99.6% |
| Texts fail 75% | 96.4% | 99.4% | 85.2% | 99.2% |
| Slow network: texts take up to 2 min | 100% | 100% | 84.2% | 99.8% |
| Hearing half as likely | 100% | 91.2% | 63.6% | 91.0% |
| Hearing a quarter as likely | 100% | 72.6% | 34.0% | 74.0% |
| Nearby scan stopped 10% of the time | 100% | 92.0% | 75.6% | 93.4% |
| Nearby scan stopped 25% of the time | 100% | 80.6% | 65.0% | 81.2% |
| Worst together (texts fail 50%, hearing half, scan stopped 25%) | 100% | 75.2% | 52.4% | 73.8% |

Median times at the observed setting: SMS 14.6 s, Bluetooth at 5 m 25.9 s,
text fails then Bluetooth 22.9 s.

## What it shows

- **SMS** meets 95% even when three texts in four fail, because the app
  tries again every 10 seconds; only a gateway that never receives (it was
  off on 12 November) stops it.
- **Bluetooth at about 5 m** meets 95% at the speed seen on the real phones,
  and when the text fails, Bluetooth carries the SOS just as well.
- **Bluetooth at 15 to 20 m** meets 95% only if the far phone hears the
  advert within about 35 seconds on average (2% a second gives 97.8%). That
  distance was never measured, so the field trial's F3 row decides it.
- What breaks the target is a **nearby phone that is not listening**: when
  its scan has stopped one time in ten, the rate falls to about 92%. This
  is why build 31 restarts the scan every 10 minutes and on every screen
  change, and why the trial should keep both phones on build 31.

It does not replace the field trial: the radio settings are assumptions,
set from two phones and 11 offline SOS.
