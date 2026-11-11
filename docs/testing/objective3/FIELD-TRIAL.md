# Objective 3 field trial: steps

The controlled simulation testing of Chapter 3, on real phones. It gives
the success rate for Chapter 4: **S_rate = N_success / N_total × 100**.

## What you need

| Item | Notes |
|---|---|
| **Sender phone** (the POCO) | The S.A.G.I.P. app, newest build, signed in as a resident. A SIM **with load** (an SMS SOS is paid by the sender) |
| **Gateway phone** (the Oppo) | SMS Gateway for Android running, as it is now |
| **Relay phone** | A second phone with the S.A.G.I.P. app signed in (any account) and **internet on**. The Oppo can do this if there is no third phone |
| **Dispatcher** | staff.sagip.me open, signed in, to watch the board and close each test SOS |
| **Tally sheet** | `field_tally_template.csv`, one row per press, filled in during the trial |

## Before you start

1. On A3 (Configuration), check that the SMS gateway number is set.
2. **A success is an SOS on the board within 3 minutes of the press**
   (decided by Joshua, 2026-11-12: "in emergency time is really crucial";
   plan Q44). During development every Bluetooth and SMS SOS made it within
   3 minutes (the slowest relay took 2 min 41 s).
3. Tell the dispatcher: **close each test SOS as soon as it appears** (Mark
   as false report). A new SOS from the same account within 10 minutes
   of an open one **joins** that one instead of making a new incident, so
   without this the presses would be counted as one.
4. Write the start time of each condition on the tally sheet. The query
   reads the server's records by time.

## The conditions (20 presses each)

A press counts as an attempt when the SOS button is held for 2 seconds and
the app shows the SOS as saved or sent. Wait until it appears on the board
(or 3 minutes pass; note a late arrival in the remarks) and the dispatcher
closes it before the next press.

| # | Condition | Sender phone settings | Expected tier |
|---|---|---|---|
| T1 | **SMS only** | Mobile data **off**, Wi-Fi **off**, airplane mode **off** (signal on), Bluetooth **off** | SMS |
| T2 | **Bluetooth relay, close** | Airplane mode **on**, then Bluetooth **on**. Relay phone within **5 m**, app open, internet on | Bluetooth relay |
| T3 | **Bluetooth relay, farther** | As T2, relay phone at **15 to 20 m** (another room or across the street) | Bluetooth relay |
| T4 | **SMS fails, relay takes over** | Signal on but no load (or remove load), data off, Bluetooth **on**, relay phone within 5 m | Bluetooth relay |
| T5 | **Total outage, then back** (optional) | Airplane mode on, Bluetooth off, nobody nearby; after 5 minutes turn data on | App, after the outage |

T1 to T4 are the outage conditions for the 95% figure: 80 attempts. T5
shows that nothing is lost when no tier can work; report it apart, not in
the 95%.

Repeat a condition if something outside the test went wrong (for example,
the relay phone's app was closed by the phone). Note it in the remarks;
do not drop the row.

## Counting

For each condition: **N_total** = presses on the tally sheet, **N_success** =
those that appeared on the board within 3 minutes of the press. The board's
timeline and `field_trial_query.sql` give the times. Enter each condition's
attempt count on A4 (Analytics, "SOS attempts in the trial") to see the
rate there too.

| Condition | N_total | N_success (within 3 min) | S_rate |
|---|---:|---:|---:|
| T1 SMS only | 20 | | |
| T2 Relay, 5 m | 20 | | |
| T3 Relay, 15 to 20 m | 20 | | |
| T4 SMS fails, relay | 20 | | |
| **T1 to T4** | **80** | | |

## After the trial

Send me the tally sheet and the start times. I run `field_trial_query.sql`
on the hosted project, fill in Chapter 4 section 4.3, and remove nothing:
the trial SOS stay on record as false reports.
