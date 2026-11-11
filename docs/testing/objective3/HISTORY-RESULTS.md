# Objective 3: every real SOS the system has received (development testing)

Joshua, 2026-11-12: "you can check the history of our system there are
testing we already made, so check it out and use it also".

**Source:** `incident_report` on the hosted project, `origin = 'sos'` and
not simulated, 12 October to 12 November 2026. That is 71 SOS sent by the
team from real phones while the system was being built and tested. One row
per SOS is in `history_sos.csv` (id, tier, time pressed, seconds to the
server; no names, numbers, or places).

**Delay** = `received_at − captured_at`: from the press on the phone to the
SOS on the server (and so on the board).

| Tier that delivered it | SOS | Median delay | Slowest | Within 1 min | Within 3 min | Rate within 3 min |
|---|---:|---:|---:|---:|---:|---:|
| Internet (app) | 60 | 0.3 s | 29 min | 50 | 55 | 91.7% |
| Bluetooth relay | 8 | 23.8 s | 3 min 0 s (179.7 s) | 6 | 8 | 100% |
| SMS to the gateway | 3 | 15.0 s | 26.4 s | 3 | 3 | 100% |
| **All** | **71** | **0.6 s** | | **59** | **66** | **93.0%** |

## The five that took longer than 3 minutes

All five arrived over the internet after the phone had waited for it. Four
happened while the offline tiers were known to be unavailable:

| SOS | Date | Delay | Why |
|---|---|---:|---|
| INC-0166 | 2026-10-16 | 29 min | Not recorded at the time |
| INC-0185 | 2026-10-20 | 3 min 16 s | Airplane mode had turned Bluetooth off; delivered when Wi-Fi came back (PROGRESS.md, the first two-phone relay try) |
| INC-0188 | 2026-10-20 | 10 min 7 s | The same session (relay faults then fixed) |
| INC-0189 | 2026-10-20 | 10 min 54 s | The same session |
| INC-0222 | 2026-11-12 | 20 min 37 s | The gateway phone (Oppo) had shut down, so no SMS could be received |

## After the 12 November fixes (builds 29 to 31)

INC-0224 (SMS, 15.0 s), INC-0226 (Bluetooth, 37.5 s), INC-0227 and INC-0228
(internet, 0.3 s), and INC-0229 (Bluetooth with build 31, 9.2 s): 5 of 5
within 3 minutes. Joshua also confirmed on 2026-11-12 that the relay works
with both phones locked for more than 30 minutes.

## What this can and cannot show

- It counts only SOS that reached the server. An SOS that never arrived
  leaves no record here, so this is the share delivered **within 3
  minutes**, not a full S_rate with every press counted. The field trial
  (`FIELD-TRIAL.md`) counts every press.
- Most of these (60 of 71) went over the internet, not during an outage.
  The outage tiers delivered 11 (8 Bluetooth, 3 SMS), all within 3 minutes.
- They were not controlled: one tester, two phones, conditions changing as
  faults were found and fixed.
