# Objective 3 testing: SOS transmission during internet outages

*Objective 3: at least a 95% successful transmission rate of SOS distress
signals during simulated internet outages, through a multi-tiered offline
mode (Bluetooth Low Energy mesh and SMS fallback).*

Formula (Chapter 3): **S_rate = N_success / N_total × 100**, where a
success is an SOS that reaches the server **within 3 minutes** of the
press (Joshua, 2026-11-12: "in emergency time is really crucial"; plan
Q44). The Analytics page (A4) shows this rate in bold, green at 95% or
more.

There are two tests:

| Test | What it shows | Status |
|---|---|---|
| **A. Software simulation** (this folder) | The app's offline logic delivers every SOS it should, in each outage condition, once, with its original time and place | **Done 2026-11-12**: results below |
| **B. Field trial on real phones** (`FIELD-TRIAL.md`) | The success rate with real radios, SIMs, and the gateway phone, as Chapter 3 describes ("controlled simulation testing ... during a simulated cellular network outage") | **Not run yet**: needs the phones, a SIM with load, and the team |

Chapter 4 needs B for the 95% figure. A shows the logic is sound and that
any failure in B comes from radios, signal, or settings, not from the
software.

## Files

| File | What it holds |
|---|---|
| `simulation_summary.json` | Every figure of test A |
| `simulation_attempts.csv` | One row per simulated SOS (600): its condition, whether it reached the server during the outage, and by which tier first |
| `FIELD-TRIAL.md` | The steps for test B |
| `field_tally_template.csv` | The sheet the team fills in on the phones during test B |
| `field_trial_query.sql` | What the server received during test B, by tier and delay |

## A. Software simulation (`packages/shared/test/objective3_simulation_test.dart`)

To run it again: `cd packages/shared`, then
`SAGIP_EVAL=1 flutter test test/objective3_simulation_test.dart`.

**What is the real app code:**
- the phone's queue and its order of tiers: data first, then SMS, then
  Bluetooth (`SyncEngine`);
- the SMS message the gateway reads (`SosSms`, the same format as the
  `sms-intake` function, checked against shared test vectors);
- the 24-byte Bluetooth packet (`SosRelayPacket`);
- the nearby phone's relay: keep, pass on, upload once (`RelayNode`);
- the gateway's reply that tells the phone its SMS arrived.

**What is simulated:** the radios, the SIM, the gateway phone, and the
server, which keeps one incident per SOS id (as the database does).

**Method:** 100 SOS per condition, one a minute, each at a random point
near one of Manila's 897 barangay centers. After the outage, the internet
returns, and everything still on a phone is sent, so duplicates and lost
records would show.

| Condition | Attempts | Reached the server during the outage | By | Success rate |
|---|---:|---:|---|---:|
| C0. Internet available (control) | 100 | 100 | App | 100% |
| C1. No mobile data, cell signal: SMS to the gateway | 100 | 100 | SMS | **100%** |
| C2. No data, no signal, a nearby phone with internet | 100 | 100 | Bluetooth relay | **100%** |
| C3. Signal but no load (the text fails), a nearby phone with internet | 100 | 100 | Bluetooth relay | **100%** |
| C4. No data, no signal; the nearby phone is offline too and reaches the internet later | 100 | 100, when the nearby phone got online | Bluetooth relay (carried) | **100%** |
| C5. No data, no signal, nobody nearby | 100 | 0 (kept on the phone) | App, when the internet returned | 0% during the outage, 100% after |

**Totals over the outage conditions (C1 to C5): 400 of 500 (80%) without
the sender's own internet; 400 of 400 (100%) where SMS or a nearby phone was
available.** All 600 SOS reached the server in the end.

Checks over all 600:

| Check | Result |
|---|---|
| Incidents created per SOS (an SOS sent by two tiers counts once) | 1 for every SOS; 0 duplicates (the server received 1,000 copies for 600 SOS) |
| Capture time kept (never the send time) | exact in every case (largest difference 0 s) |
| Location kept | largest difference 0.77 m (SMS and the packet carry 5 decimals) |
| SMS messages the gateway could not read | 0 |
| The phone shows "delivered" for every SOS at the end | 600 of 600 |

**What this means:** whenever SMS or a nearby phone is available, the
software gets the SOS out without the sender's internet, every time. When
neither is available (C5), no tier can work, and the SOS waits on the phone
until the internet returns, as designed. The real rate therefore depends on
how often, in a real outage, the resident has signal and load, or a phone
with the app is within Bluetooth range. Test B measures that.

## Field evidence so far (development testing, not a controlled trial)

SOS received on the hosted project from 12 October to 10 November 2026,
by the tier that delivered them first (team test SOS):

| Tier | Delivered | Median delay (capture to receipt) | Within 1 minute | **Within 3 minutes** | Within 5 minutes |
|---|---:|---:|---:|---:|---:|
| Internet (app) | 56 | 0.2 s | 48 | **52** | 53 |
| Bluetooth relay (two phones) | 5 | 22.1 s | 4 | **5** | 5 |
| SMS to the gateway | 1 | 0.5 s | 1 | **1** | 1 |

The number of attempts was not counted, so no success rate can be taken
from these.
