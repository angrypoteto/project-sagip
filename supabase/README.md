# Supabase backend

The hosted project is **Project S.A.G.I.P** (`imssgenjfirpohkwxwbv`, Seoul region). The dashboard connects to it when `apps/dashboard/.env` holds `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (copy `.env.example`). Without that file the dashboard runs on mock data.

## What is here

| Path | What it is |
|---|---|
| `migrations/*_core_schema.sql` | Tables: staff, residents and households, units, incidents and their timeline, crowd reports, dispatches, weather, audit log |
| `migrations/*_access_control.sql` | Row Level Security, read-only grants, board and resident views, realtime |
| `migrations/*_dispatch_actions.sql` | Every write the app can make (verify, SMS check, false report, confirm type, assign, resolve, reveal a number), the audit trigger, and DBSCAN clustering of crowd reports |
| `migrations/*_demo_data.sql` | Sample Manila data and demo tools (SQL editor only) |
| `migrations/*_private_rls_helpers.sql` | Role-check helpers moved out of the API |
| `tests/rls_test.sql` | 29 pgTAP checks of who can see and do what |
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
- **Start over:** in the SQL editor run `select public.reset_demo_data();`. It wipes incidents, reports, residents, units, and the audit log, and reloads the sample data. Staff accounts are kept.
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

## Running the RLS test

With the Supabase CLI and Docker: `supabase start`, then `supabase test db`. The test runs in one transaction that is rolled back, so it is also safe to paste into the hosted SQL editor if it is converted to collect its results (see `docs/PROGRESS.md`, Gotchas).
