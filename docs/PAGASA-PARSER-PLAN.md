# PAGASA parser: plan (waiting for Joshua's approval)

Decision (Joshua, 2026-10-03): PAGASA will not give us API access in time, so S.A.G.I.P. reads PAGASA's public web pages and bulletins instead (plan risk 4, Q35). This file is the plan for that parser. Nothing here is built yet.

## What FR5 needs from PAGASA

The threshold engine (`weather_alert` rows, migration `alert_engine`) already turns three readings for Manila into alerts:

| Reading | Column | Thresholds now (A3) |
|---|---|---|
| Rainfall intensity | `rainfall_intensity` (mm/hr) | warning 15, critical 30 |
| Tropical cyclone wind signal | `signal_level` (0 to 5) | warning 1, critical 3 |
| Storm surge height | `storm_surge_m` (m) | warning 1.1, critical 2.1 |

So the parser only has to produce one row at a time: the current rainfall level, signal, and surge height for Metro Manila, with where and when PAGASA said it.

## Where PAGASA publishes them (checked 2026-10-03)

All three pages are plain server-made HTML (no app or login needed), so a parser can read them:

1. **Heavy Rainfall Warning, NCR** on the NCR regional page (`bagong.pagasa.dost.gov.ph/regional-forecast/ncrprsd`). When there is none it says "As of today, there is no Heavy Rainfall Warning Issued." When there is one, it lists areas under YELLOW, ORANGE, and RED warning levels (for example "ORANGE WARNING LEVEL: Metro Manila, ..."). PAGASA's levels map onto our thresholds: Yellow is 7.5 to 15 mm/hr, Orange 15 to 30, Red over 30. The parser records the lower bound of the level Metro Manila is under (Yellow 7.5, Orange 15, Red 30), so Orange becomes a warning and Red a critical alert with today's A3 values.
2. **Tropical Cyclone Bulletin** (`bagong.pagasa.dost.gov.ph/tropical-cyclone/severe-weather-bulletin`). It says "No Active Tropical Cyclone within the Philippine Area of Responsibility" when there is none. During a storm it lists the areas under each Wind Signal (1 to 5) and a storm surge section with heights. The parser reads the highest signal that names Metro Manila (or Manila) and the surge height for the Metro Manila coast. The same bulletin is also a PDF (`TCB#n_<name>.pdf`), the fallback if the HTML changes.
3. **Thunderstorm advisories** appear on the NCR page too. They are not one of our three readings; the parser can pass them on as an advisory for D10 later (not in this plan).

## How it would work

- **`ingest-pagasa` Edge Function** (Deno, in `supabase/functions/`), called every 10 minutes by `pg_cron` the same way the database already calls `send-alerts` (vault secret, `pg_net`).
- **Parse, don't guess.** Small, tested functions: `parseRainfallWarning(html)`, `parseCycloneBulletin(html)`, each returning the reading plus the issue time and the bulletin number, or "none in effect", or "could not read" (the page changed). They run in Node tests on saved copies of real pages, like the other functions.
- **Write a row only when something changed** (a new bulletin or level), with `is_simulated = false`. The existing trigger raises or ends the alerts and queues SMS and push. A reading of "none in effect" brings the levels back to 0, so alerts end.
- **Feed health:** a `feed_status` row per source (last success, last error, last bulletin seen) for D10's "PAGASA feed: last success 10 min ago" and the plan's offline/error state. If the page cannot be read three times in a row, D10 says so and dispatchers relay by hand (already possible).
- **Be polite to PAGASA:** one request per page per run, a clear User-Agent, and no faster than every 10 minutes (the pagasa-parser project asks the same).
- **Simulation mode stays.** For demos and UAT, `simulate_weather` and a replay of saved bulletins keep working; replayed rows are marked simulated.

## Test fixtures

- Saved today: the NCR page with no warning, the bulletin page with no cyclone.
- Still needed: copies of each page while a warning and a cyclone are active. Sources: PAGASA's own archive of the last cyclone's PDFs (kept one week after the last bulletin), the `pagasa-parser/bulletin-archive` mirror on GitHub (bulletins since late 2020, also useful for the LSTM's signal feature), and saving the live pages during the next rainfall warning.

## Risks

- PAGASA changes its page layout: the parser fails loudly ("could not read"), D10 shows the feed as down, and manual relay covers the gap.
- Wording varies between bulletins ("Metro Manila", "NCR", "Manila"): the area matcher accepts all three, tested on archived bulletins.
- Storm surge heights come as ranges ("1.0 to 3.0 m"): record the upper end, so a range reaching the critical height raises a critical alert. Confirm with MDRRMD.

## Files it would touch

`supabase/functions/ingest-pagasa/` (new), a migration (`feed_status`, the cron call), `supabase/tests/rls_test.sql`, the D10 feed line in the dashboard, `supabase/README.md`, `docs/PROGRESS.md`. About a day of work, plus fixtures as they come.
