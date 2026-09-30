# Supabase backend

The hosted project is **Project S.A.G.I.P** (`imssgenjfirpohkwxwbv`, Seoul region). The dashboard connects to it when `apps/dashboard/.env` holds `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (copy `.env.example`). Without that file the dashboard runs on mock data. The mobile app's database side is in place too (part 5); the app itself still runs on mock data until part 6 connects it.

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
| `tests/rls_test.sql` | 87 pgTAP checks of who can see and do what |
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

Accounts are created in the SQL editor, never in a migration, so no password is in the repo:

```sql
select public.create_staff_account('name@example.com', 'a-strong-password', 'R. Santos', 'dispatcher');
-- role: 'dispatcher', 'admin', or 'responder' (responders also take a unit id, for example 'unit-r05')
```

## How the phones use it

- Records made on a phone carry the phone's id (`client_uuid`, a UUID) and its capture time. Sending the same record again returns the stored one, so the offline queue can retry safely; the capture time is never replaced by the upload time.
- Residents sign in with their mobile number and a texted code. After the code, `link_resident()` finds their record, including one MDRRMD made before the app (same number). New numbers call `register_resident(name, barangay, district)`. Whether a number is registered is only known after the code, so nobody can look up numbers.
- Sending the codes needs Supabase's Send SMS hook (Authentication, then Hooks) pointing at an Edge Function; see part 6 in `docs/PROGRESS.md`.
- Refusals come back as short codes the app turns into its own messages: `not_allowed`, `invalid_value`, `not_found`, `incident_closed`, `outside_manila`, `rate_limited`, `no_location`, `no_assignment`, `finish_report_first`, `already_on_scene`.

## Loading all 897 barangays

`barangay` holds 10 sample rows. When the Data role delivers the full list (name, district, and ideally boundaries), load it in the Table Editor (import CSV) or a new migration. With boundaries (`boundary`, multipolygon), the Manila check for crowd reports switches from the rough box to the real boundaries automatically.

## Running the RLS test

With the Supabase CLI and Docker: `supabase start`, then `supabase test db`. The test runs in one transaction that is rolled back, so it is also safe to paste into the hosted SQL editor if it is converted to collect its results (see `docs/PROGRESS.md`, Gotchas).
