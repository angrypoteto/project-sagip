# Surge test: thousands of residents at once (NFR7)

**Date:** 2026-11-03. **Asked by:** Joshua ("what if more than thousands of
residents request at the same time? simulate it and record it on the docs").
**Run by:** Claude, on the hosted project (`imssgenjfirpohkwxwbv`, Supabase
Free plan, Postgres 17, Seoul region).

NFR7 (Chapter 3): *"handle a target surge of up to 10,000 incident reports
and SOS requests within a one-hour window ... by queuing incoming submissions
through Supabase's pooled database connections, applying per-account rate
limiting to prevent single-source flooding, and using the Priority Queue
Algorithm to rank and surface the most severe and vulnerable cases first."*
The thesis says this figure "has not been load-tested at full volume". This
is the first test of it.

## How it was run

- **Real functions, real database, nothing kept.** Throwaway residents were
  created and each sent an SOS (`submit_sos`) or a crowd report
  (`submit_crowd_report`) exactly as the app does, signed in as themselves
  (row level security on). Every run was one transaction that ended with an
  error on purpose, so Postgres undid all of it: no resident, incident, push,
  SMS, or Facebook post was kept or sent. The record counters, which Postgres
  does not undo, were put back after every run (`supabase/tests/surge_restore.sql`).
  Checked after the last run: no test resident, user, or incident left; the
  next numbers unchanged (res-107, INC-0212, rep-317).
- **The mix:** residents spread over all 897 barangays; one in seven with a
  consented vulnerable household (senior, PWD, pregnant); one SOS in 200 with
  fake GPS. Capture times spread over the last hour, as a real surge.
- **Measured inside the database:** the time of each call, the dispatcher's
  board query (`incident_board`, as the dashboard reads it, signed in as a
  dispatcher), the Priority Queue order, and the per-account limits.
- **Scripts:** `supabase/tests/surge_test.sql` (SOS),
  `supabase/tests/surge_reports_test.sql` (crowd reports),
  `supabase/tests/surge_restore.sql` (afterwards, every time).

## Results

### SOS (FR1, FR2, FR8)

| | 1,000 SOS | **10,000 SOS (NFR7's hour)** |
|---|---:|---:|
| Time to store all of them | 0.56 s | **5.6 s** |
| Per second | 1,802 | **1,778** |
| Per SOS: average / median / 95th / 99th percentile / slowest | 0.53 / 0.48 / 0.57 / 0.83 / 35.6 ms | **0.54 / 0.50 / 0.74 / 0.87 / 12.6 ms** |
| First tenth vs last tenth (does it slow as the table grows?) | 0.91 vs 0.49 ms | **0.534 vs 0.535 ms (no)** |
| Dispatcher's board query (all open incidents) | 48 to 61 ms | **473 to 480 ms** |
| Size of that board for the dashboard | | **10.5 MB** |
| Vulnerable households ranked first | 142 of 142 in the top 142 | **1,420 of 1,428 in the top 1,428** |
| Best rank of an SOS with fake GPS | 923rd | 1,298th |

- **The database stores SOS far faster than NFR7 needs.** 10,000 an hour is
  about 3 a second; one connection stored about 1,800 a second, and the
  time per SOS did not grow from the first to the ten-thousandth.
- **The Priority Queue does what FR2 and NFR7 ask.** Vulnerable households
  come first; the 8 vulnerable SOS below the top 1,428 were passed by older
  SOS through the waiting-time factor, as the rule intends. Fake-GPS SOS are
  pushed down (FR8).
- Three sessions of 3,000 SOS each also ran, about 1,750 to 2,000 a second
  each, but the connector ran them one after another, not at the same time,
  so this is **not** a concurrency result.

### Crowd reports (FR7, FR12, FR15)

| Reports in the hour | Total time | Per report, by position in the hour |
|---:|---:|---|
| 600 | 7.6 s | 10.9 ms (101 to 200) rising to 14.0 ms (501 to 600) |
| 2,000 | 32.0 s | 11.5 ms (1 to 250) rising to 27.3 ms (1,751 to 2,000) |
| 3,000 | did not finish within the connector's limit (about 2 minutes, with setup) | |

- Every report was typed by the classifier (600 of 600; FR12).
- Clusters formed as FR7 says: 10 hotspots gave 5 cluster incidents with 103
  reports (hotspots within 50 m of each other merged); 2,000 scattered
  reports gave 159 small clusters.
- **Per-account limit works for crowd reports:** an account that had sent
  one report could send 4 more, then every further one was refused
  (`rate_limited`, 5 an hour, A3).
- **A crowd report costs 20 to 50 times an SOS, and more as the hour
  fills,** because every new report re-clusters all reports of the last 60
  minutes and walks every cluster again (finding 3).

## Findings

| # | Finding | Severity | Status |
|---|---|---|---|
| 1 | **Record numbers were cut to a fixed width.** `lpad` shortens longer numbers: the 1,000th resident got `res-100` (already taken), so **every registration after the 999th would fail**; incident 10,000 would become `INC-1000` and clash the same way, inside NFR7's own 10,000; NDRRMC report 10,000 likewise. Found before the first run finished. | Critical | **Fixed:** migration `20261103055558_id_width.sql` (pad to at least the width, never cut: res-1000, INC-10000; existing numbers unchanged), checked in a rolled-back run, used in every run above, applied to the hosted project with Joshua's yes on 2026-11-03. |
| 2 | **No per-account limit on SOS.** One account sent 200 SOS in a row and all 200 were stored; NFR7 promises "per-account rate limiting to prevent single-source flooding". Crowd reports are limited (5 an hour); SOS are not, on purpose, since an SOS must never be refused. | High | Open. Proposed: a new SOS from an account that already has an open SOS from the last 10 minutes joins that one (the same incident, its location updated) instead of adding another; nothing is refused. |
| 3 | **Crowd report clustering slows as reports pile up.** Each report re-runs DBSCAN over the whole last hour: 11 ms per report at the start, 27 ms after 2,000; 10,000 in an hour would reach hundreds of ms each. Also, two reports arriving at the same instant could each create an incident for the same new cluster (each re-cluster runs without a lock). | Medium | Open. Proposed: cluster only the reports near the new one (within 100 m, by spatial index), and take a lock while re-clustering. |
| 4 | **The dashboard reloads the whole board on every change.** With 10,000 open incidents the board is 10.5 MB and takes 0.48 s on the server; during a surge (3 new SOS a second) the dashboard would ask for it several times a second. | Medium | Open. Proposed: load only what changed, or page the queue (the first few hundred by priority, the rest on request). |
| 5 | **The Free plan, not the database, is the ceiling.** Supabase Free allows **200 concurrent Realtime connections and 100 messages a second** (supabase.com/docs/guides/realtime/limits), and this database 60 connections. Every open app holds a Realtime connection, so a few hundred residents with the app open at once would already exceed it. Pro without a spend cap allows 10,000 connections and 2,500 messages a second. | High for a pilot; none for the defense demo | A plan decision (already noted before a pilot: Supabase Pro). |

## What was not tested

- **Many phones at the same moment over the internet.** Only the database
  was measured. The way in (Supabase's API gateway, sign-in, and the
  connection pooler) and real simultaneous connections were not: the
  connector runs one query at a time, and sending from many devices needs
  many signed-in accounts. A k6 or Artillery run against a paid test
  project would answer this.
- **What reaches residents after the surge:** push through Firebase (one
  topic message per alert, so unaffected by the number of residents), and
  SMS through the gateway phone, which sends one text at a time and is
  capped at 500 a day (A3). SMS replies to thousands of SOS texts would take
  hours; an SMS provider would be needed at that scale.
- **The dashboard drawing 10,000 incidents** on a dispatcher's computer.

## For Chapter 4

"A surge of 10,000 SOS requests, the NFR7 target, was simulated on the
hosted database: all were stored in 5.6 seconds (about 1,780 per second;
median 0.50 ms each), the vulnerable cases were ranked first, and fake-GPS
requests were pushed down. Crowd reports, which are clustered on arrival,
cost 11 to 27 ms each as the hour filled. The test found that record numbers
were truncated after resident 999 and incident 9,999 (fixed), that SOS had
no per-account limit, and that the Free hosting plan allows 200 concurrent
app connections, below the target; concurrent network load was not tested."
