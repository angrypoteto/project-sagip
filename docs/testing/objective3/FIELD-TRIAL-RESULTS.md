# Objective 3 field trial: results

The run of `FIELD-TRIAL.md` on real phones. Per-press data:
`field_tally.csv` (one row per counted press). The relay fix made during
the trial and its checks: `relay_fix_checks.csv`.

**Result: 78 of 78 counted SOS reached the dispatcher's board within
3 minutes (100%).** T2 and T3 have 19 counted presses each; one more press
in each makes the planned 20.

## Set-up

| Role | Phone | Notes |
|---|---|---|
| Sender | POCO (Android, Xiaomi HyperOS) | S.A.G.I.P. signed in as a resident; pressed over USB (`adb`), so every press was the same 2.6 s hold |
| Relay (T2 to T4) | Oppo (Android, ColorOS) | S.A.G.I.P. signed in as another resident, online, app open |
| Gateway (T1) | The gateway phone with the gateway SIM | Receives the SOS texts |
| Board | staff.sagip.me | Each test SOS was closed as a false report as soon as it appeared, so the next press made a new incident |

Dates and builds:
- 2026-11-12: T1 (all 20) and T2 press 2, on build 31.
- 2026-11-16: the rest of T2, T3 presses 1 to 10, on build 31; T3 presses
  11 to 20 and all of T4 on build 32 (the relay retry fix, below).

Between presses the sender went back online for a few seconds so the app
learned that its last SOS was closed (the app keeps one open SOS at a
time), then offline again for the next press.

## How the time was measured

- **Pressed at:** the sender's own capture time, stored with the SOS
  (`captured_at`). The laptop's clock at the press agreed with it to the
  second.
- **On the board at:** the server's time the SOS arrived (`received_at`),
  which is when it appears on the dispatcher's board.
- **Delivery time** = on the board minus pressed.

## Conditions

| | Condition | Sender | Relay |
|---|---|---|---|
| T1 | SMS only | Mobile data off, signal on, SIM with load | none |
| T2 | Bluetooth relay, close | Airplane mode on, Bluetooth on, Wi-Fi off | within 5 m |
| T3 | Bluetooth relay, farther | as T2 | about 15 to 17 m away, indoors, 2 walls between (in the kitchen) |
| T4 | SMS fails, relay takes over | Airplane mode off, signal on, data and Wi-Fi off, Bluetooth on; only a SIM with **no load** in the phone | within 5 m |

T4 check: on every counted T4 press the sender's screen showed
"SMS: Couldn't send", then "Passing to nearby phones". With a second SIM
with load in the phone the text went out on that SIM, so for T4 only the
no-load SIM was left in the phone.

## Results

| Condition | Counted | On the board within 3 min | Fastest | Median | Mean | Slowest | Within 10 s |
|---|---:|---:|---:|---:|---:|---:|---:|
| T1 SMS only | 20 | 20 (100%) | 4.3 s | 5.5 s | 6.5 s | 17.6 s | 18 |
| T2 relay, within 5 m | 19 | 19 (100%) | 1.3 s | 5.4 s | 5.5 s | 10.5 s | 18 |
| T3 relay, 15 to 17 m, 2 walls | 19 | 19 (100%) | 0.8 s | 1.8 s | 2.7 s | 9.8 s | 19 |
| T4 SMS fails, relay | 20 | 20 (100%) | 1.0 s | 3.9 s | 6.0 s | 29.6 s | 18 |
| **T1 to T4** | **78** | **78 (100%)** | 0.8 s | **4.8 s** | 5.2 s | 29.6 s | 73 |

Every SOS arrived by the channel the condition was testing: T1 as an SMS
SOS, T2 to T4 as "Bluetooth relay" on the board.

## The relay fix found during the trial (build 32)

During T3 a relay phone held an SOS it had received over Bluetooth
("Passing on 1 SOS from a nearby phone") and did not upload it, while
the same phone's own SOS went through over its internet.

**Cause** (`packages/shared/lib/src/offline/relay.dart`, `uploadAll`):
when the relay's upload failed because its connection dropped for a
moment, it tried again only when the phone went offline and online again,
or when it heard the same SOS again. Android often reports a nearby
Bluetooth advert only once, so a relay that still counted as online
could keep the SOS until the sender came back online itself.

**Fix:**
- While the relay counts as online and still carries an SOS it could not
  upload, it tries again every 5 seconds.
- An upload with no answer within 15 seconds counts as no internet, so
  a hung request on a weak connection does not block the rest.
- Three new tests in `packages/shared/test/relay_test.dart` (a failed
  upload retried with no new advert; a hung upload timed out and retried;
  no retries while offline). All 22 relay tests pass; `flutter analyze`
  clean.
- App build 31 → 32, installed on both phones on 2026-11-16.

**Checks on the two phones with build 32** (`relay_fix_checks.csv`):

| Check | Result |
|---|---|
| S1 normal relay | on the board in 1.6 s |
| S2 relay screen just turned off | 1.4 s |
| S3 relay app in the background | 1.5 s |
| S4 relay offline while carrying, then its Wi-Fi back on | on the board 2.3 s after its Wi-Fi came on |
| S5 no relay nearby | waited on the sender ("Offline · 1 waiting to send"), sent 23.8 s after the sender's Wi-Fi came on, with its original press time |
| S2b relay screen off, phone still on USB | 1.6 s |
| S2c relay unplugged, screen off 5 minutes | 1.2 s |

S4 shows a relay that comes back online delivers; the exact failure
(counted as online, upload failed, not retried) is covered by the new unit
test.

## Limits

- One sender and one relay phone, both mid-range Android phones; other
  makers handle Bluetooth and background apps differently.
- One place (a house), indoors; T3's distance was estimated, not measured.
- The relay phone had its screen on or had just been woken in the
  counted presses.
- The presses were made over USB, so the hold is the same every time; a
  person's press is not timed here (it is the same 2-second hold).
