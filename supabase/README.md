# Supabase backend

The hosted project is **Project S.A.G.I.P** (`imssgenjfirpohkwxwbv`, Seoul region). The dashboard connects to it when `apps/dashboard/.env` holds `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (copy `.env.example`). Without that file the dashboard runs on mock data. The mobile app connects the same way with `apps/mobile/.env` (part 6); without it the app runs on sample data.

## What is here

| Path | What it is |
|---|---|
| `migrations/*_core_schema.sql` | Tables: staff, residents and households, units, incidents and their timeline, crowd reports, dispatches, weather, audit log |
| `migrations/*_access_control.sql` | Row Level Security, read-only grants, board and resident views, realtime |
| `migrations/*_dispatch_actions.sql` | Every write the app can make (verify, SMS check, false report, confirm type, assign, resolve, reveal a number), the audit trigger, and DBSCAN clustering of crowd reports |
| `migrations/*_demo_data.sql` | Sample Manila data and demo tools (SQL editor only) |
| `migrations/*_private_rls_helpers.sql` | Role-check helpers moved out of the API |
| `migrations/*_mobile_schema.sql` | For the phones: barangays (10 samples), client ids and capture times on SOS and reports, the on-scene check, completion reports, alerts and read state, 72-hour forecasts, data deletion requests |
| `migrations/*_mobile_actions.sql` | Every write the phones can make (resident sign-up and linking, SOS and details, crowd reports with the Manila check and hourly limit, consent and household, responder accept, arrive, on-scene check, status, completion report, position, alert read) and the reads in the app's shapes (`my_sos`, `my_crowd_reports`, `my_assignments`, `my_unit_history`, `my_alerts`); DBSCAN now counts from capture time |
| `migrations/*_mobile_demo_data.sql` | `reset_demo_data()` also loads past rescues for R-03 and Maria, four sample alerts, and sample forecasts |
| `migrations/*_sms_log.sql` | The SMS log: every text sent or kept; no client access |
| `migrations/*_accounts.sql` | A1: `admin_create_staff` (temporary password returned once), `admin_update_staff`, `admin_set_staff_active` (bans the login and ends sessions), `admin_reset_password`, `admin_set_resident_suspended`; every role check ignores deactivated accounts; suspended residents cannot send crowd reports, and their SOS arrives unverified |
| `migrations/*_resources.sql` | A2: units can be retired (`retired_at`) and are then never dispatched; `save_unit`, `retire_unit`, `restore_unit`, `set_responder_unit` (admins only, audited) |
| `migrations/*_analytics.sql` | `analytics_report(from, to)` for A4 (admins only): counts, dispatch, verification, response, and travel times from the incident timeline, SOS by channel, breakdowns by type, barangay, unit, and Manila day, and the Dijkstra timings |
| `migrations/*_configuration.sql` | A3 settings (`app_setting`: the Triage Queue priority weights), `set_setting` (admins only, audited as `settingChanged`), and the priority score, severity, and factors on `incident_board` |
| `migrations/*_routing.sql` | Road routes on dispatch records (`dispatch.route` polyline and `route_plan`; `assign_unit` takes the route), routes in `my_assignments`, and the Dijkstra timing log `routing_run` (admins read it; `log_routing_run` writes it) |
| `migrations/*_sms_intake.sql`, `*_sms_gateway_provider.sql` | Tier 2: `intake_sms_sos` (service role only) files an SOS texted to the gateway SIM, finding the resident by the sender's number; `submit_sos` attaches the resident when the app's copy of an SOS texted from another SIM arrives; inbound texts logged in `sms_log` |
| `functions/sms-intake/` | Receives texts from the gateway SIM, checks the SAGIP1 format and checksum, files the SOS, and returns the reply for the gateway to send; `sms_intake.test.ts` runs with `node --test` |
| `functions/send-sms/` | The Send SMS hook for sign-in codes (Semaphore, or kept in `sms_log` without it); `sms.test.ts` runs with `node --test` |
| `tests/rls_test.sql` | 158 pgTAP checks of who can see and do what |
| `seed.sql` | Loads the sample data on a local database |

Migration file names match the versions recorded on the hosted project. Never edit an applied migration; add a new file.

## Changing the demo data

- **Small edits:** open the Table Editor in the Supabase dashboard and edit rows directly (for example a unit's status or a resident's household). Items with an eye icon are **views** and cannot be edited; change the table they read from:

  | View | Edit instead |
  |---|---|
  | `incident_board` | `incident_report` (the timeline is `incident_event`) |
  | `resident_profile`, `vulnerable_resident_list` | `manila_resident` (name, full number, barangay, consent) and `vulnerable_member` (household members) |

  A resident is on the Vulnerable Resident Priority List only when `consent_given_at` is set and they have at least one `vulnerable_member` row. The dashboard updates live, except for edits to `manila_resident` (not sent over Realtime because it holds full numbers): reload the page after those.
- **Moving an incident through its steps** (assign, en route, on scene, resolved): use the dashboard or `demo_advance()` below, not direct edits, so unit status and incident status stay in step.
- **Start over:** in the SQL editor run `select public.reset_demo_data();`. It wipes incidents, reports, residents, units, alerts, forecasts, completion reports, and the audit log, and reloads the sample data. Staff accounts and barangays are kept. Run it once after the mobile migrations to get the sample alerts, forecasts, and past rescues.
- **Alerts and forecasts:** add rows to `public_alert` (an empty `barangays` list means all of Manila; set `expires_at` to hide one later) and `barangay_forecast` (the newest row per barangay is the current forecast).
- **Change the sample data for good:** edit it in a new migration that replaces `public.reset_demo_data()`, then run the function.

Demo tools (SQL editor):

```sql
select public.demo_new_sos();           -- a new SOS arrives (Barangay 128, Tondo, flagged mock location)
select public.demo_add_crowd_report();  -- a third Dapitan St report; DBSCAN turns the three into a confirmed incident
select public.demo_advance();           -- every assigned incident moves one step: en route, on scene, resolved
```

## Staff accounts

Admins create accounts on the dashboard (Accounts page); the temporary password is shown once. In the SQL editor, without a password in the repo:

```sql
select public.create_staff_account('name@example.com', 'a-strong-password', 'R. Santos', 'dispatcher');
-- role: 'dispatcher', 'admin', or 'responder' (responders also take a unit id, for example 'unit-r05')
```

## How the phones use it

- Records made on a phone carry the phone's id (`client_uuid`, a UUID) and its capture time. Sending the same record again returns the stored one, so the offline queue can retry safely; the capture time is never replaced by the upload time.
- Residents sign in with their mobile number and a texted code. After the code, `link_resident()` finds their record, including one MDRRMD made before the app (same number). New numbers call `register_resident(name, barangay, district)`. Whether a number is registered is only known after the code, so nobody can look up numbers.
- Sending the codes needs Supabase's Send SMS hook (Authentication, then Hooks) pointing at an Edge Function; see part 6 in `docs/PROGRESS.md`.
- Refusals come back as short codes the app turns into its own messages: `not_allowed`, `invalid_value`, `not_found`, `incident_closed`, `outside_manila`, `rate_limited`, `no_location`, `no_assignment`, `finish_report_first`, `already_on_scene`.

## Turning on resident sign-in by SMS code (for Joshua)

The app asks Supabase to text a code; Supabase hands the code to the `send-sms` Edge Function (a "Send SMS hook"), which sends it through Semaphore. Until the Semaphore account exists, the function sends nothing and keeps the message (with the code) in the `sms_log` table for an hour, so the demo still works.

1. **Deploy the function** (Supabase CLI, in the repo root): `supabase functions deploy send-sms --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`. Or ask Claude to deploy it through the Supabase connector.
2. **Turn on phone sign-in:** Authentication > Sign In / Providers > Phone: enable it. The SMS provider fields can stay empty when the hook is used.
3. **Point the hook at the function:** Authentication > Hooks > Send SMS hook > Add: type HTTPS, URL `https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/send-sms`. Click "Generate secret" and copy it (it starts with `v1,whsec_`).
4. **Give the function its secrets:** Edge Functions > Secrets: `SEND_SMS_HOOK_SECRET` = the secret from step 3. Later, when the account exists: `SEMAPHORE_API_KEY`, and `SEMAPHORE_SENDER_NAME` once Semaphore approves it.
5. **Try it:** in the app, enter a number and tap Send code. Without Semaphore, read the code in the Table Editor: `sms_log`, newest row. With Semaphore, the phone gets a text.
6. **For demos without texts at all:** Authentication > Sign In / Providers > Phone > Test phone numbers: for example `639170004821=123456` (Maria's sample number). Test numbers never call the hook.

The function never logs full numbers (only "0917 ••• 4821"), and `sms_log` is not readable from the apps.

## Tier 2: SOS by SMS (for Joshua, when the gateway SIM exists)

When a phone has signal but no data, the app texts the SOS to the MDRRMD gateway SIM in a short checked format (`SAGIP1 SOS <id> <lat>,<lng> <accuracy> <time> <flags> <crc>`). The gateway forwards each text to `sms-intake`, which files the SOS; the app's later internet copy is recognised by the same id.

1. **Gateway phone:** a spare Android phone with the gateway SIM, running an SMS gateway app that forwards received texts to a webhook (for example SMS Gateway for Android). Set its webhook to `https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/sms-intake` with the header `x-sagip-key: <secret>`.
2. **Deploy:** `supabase functions deploy sms-intake --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`.
3. **Secrets:** `SMS_INTAKE_SECRET` = the same secret. Optional: `SMS_ACK_VIA_SEMAPHORE=true` to send the reply through Semaphore; otherwise the response's `reply` is for the gateway to send from its SIM.
4. **Phones:** put the gateway SIM's number in `apps/mobile/.env` as `SMS_GATEWAY_NUMBER` and rebuild. Residents allow SMS on the welcome screen.
5. **Try it:** turn off mobile data on a test phone (keep signal), hold SOS; the board shows it as an SMS SOS within seconds. Unreadable texts are in `sms_log` (`kind = 'inbound'`, `status = 'unreadable'`).

## Priority weights (A3)

The Triage Queue ranks by the weights in `app_setting` (provisional until MDRRMD's triage SOP arrives). Change them on the dashboard's Configuration page (admins), which checks each value's range and that High stays at or below Critical; every change is in the audit log. `incident_board` returns each incident's `priority_score`, `priority_severity`, and `priority_factors` computed with those weights (the same rules as `PriorityRules` in `packages/shared`). From the SQL editor, `select public.set_setting(...)` works only as an admin account; edit the table directly there instead if needed (that change is not audited).

## Routing and the timing log

The dashboard ranks units by road travel time (Dijkstra over the OpenStreetMap road graph bundled in the apps; see `ml/README.md`). On Assign it sends the unit's route, which `assign_unit` keeps on the dispatch record: `route` holds the encoded polyline and `route_plan` the travel time, length, street steps, and how long Dijkstra took. The responder's phone gets it through `my_assignments()` and also routes on its own from its current position.

Every Dijkstra run is timed and logged in `routing_run` (at most one per job and kind a minute from each app). For Chapter 4, in the SQL editor:

```sql
select kind, platform, count(*), round(avg(compute_ms), 2) as avg_ms,
       percentile_cont(0.95) within group (order by compute_ms) as p95_ms, max(compute_ms) as max_ms
from public.routing_run group by kind, platform order by kind, platform;
```

## Loading all 897 barangays

`barangay` holds 10 sample rows. When the Data role delivers the full list (name, district, and ideally boundaries), load it in the Table Editor (import CSV) or a new migration. With boundaries (`boundary`, multipolygon), the Manila check for crowd reports switches from the rough box to the real boundaries automatically.

## Running the RLS test

With the Supabase CLI and Docker: `supabase start`, then `supabase test db`. The test runs in one transaction that is rolled back, so it is also safe to paste into the hosted SQL editor if it is converted to collect its results (see `docs/PROGRESS.md`, Gotchas).
