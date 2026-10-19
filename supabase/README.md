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
| `migrations/*_mobile_schema.sql` | For the phones: barangays (10 samples; all 897 come from `data/`, see "Loading all 897 barangays"), client ids and capture times on SOS and reports, the on-scene check, completion reports, alerts and read state, 72-hour forecasts, data deletion requests |
| `migrations/*_mobile_actions.sql` | Every write the phones can make (resident sign-up and linking, SOS and details, crowd reports with the Manila check and hourly limit, consent and household, responder accept, arrive, on-scene check, status, completion report, position, alert read) and the reads in the app's shapes (`my_sos`, `my_crowd_reports`, `my_assignments`, `my_unit_history`, `my_alerts`); DBSCAN now counts from capture time |
| `migrations/*_mobile_demo_data.sql` | `reset_demo_data()` also loads past rescues for R-03 and Maria, four sample alerts, and sample forecasts |
| `migrations/*_sms_log.sql` | The SMS log: every text sent or kept; no client access |
| `migrations/*_accounts.sql` | A1: `admin_create_staff` (temporary password returned once), `admin_update_staff`, `admin_set_staff_active` (bans the login and ends sessions), `admin_reset_password`, `admin_set_resident_suspended`; every role check ignores deactivated accounts; suspended residents cannot send crowd reports, and their SOS arrives unverified |
| `migrations/*_web_form.sql` | W1 to W3: `submit_crowd_report` records the channel (`p_source`: `app` or `webForm`), the hourly report limit moves to `app_setting` (`reports.per_hour`, set on A3), `my_report_quota()` tells a resident how many reports are left this hour, and `my_crowd_reports()` returns each report's channel |
| `migrations/*_alert_engine.sql` | The rest of A3 and the threshold engine: settings for alert thresholds, channel switches, the hotline and SMS gateway number, and simulation mode; `client_config()` (the two numbers, readable before sign-in); a trigger on `weather_alert` that issues an alert when a reading crosses a threshold; `alert_delivery` (one row per alert and channel); `simulate_weather` (admins, simulation mode only, audited) |
| `migrations/*_resources.sql` | A2: units can be retired (`retired_at`) and are then never dispatched; `save_unit`, `retire_unit`, `restore_unit`, `set_responder_unit` (admins only, audited) |
| `migrations/*_analytics.sql` | `analytics_report(from, to)` for A4 (admins only): counts, dispatch, verification, response, and travel times from the incident timeline, SOS by channel, breakdowns by type, barangay, unit, and Manila day, and the Dijkstra timings |
| `migrations/*_configuration.sql` | A3 settings (`app_setting`: the Triage Queue priority weights), `set_setting` (admins only, audited as `settingChanged`), and the priority score, severity, and factors on `incident_board` |
| `migrations/*_routing.sql` | Road routes on dispatch records (`dispatch.route` polyline and `route_plan`; `assign_unit` takes the route), routes in `my_assignments`, and the Dijkstra timing log `routing_run` (admins read it; `log_routing_run` writes it) |
| `migrations/*_sms_intake.sql`, `*_sms_gateway_provider.sql` | Tier 2: `intake_sms_sos` (service role only) files an SOS texted to the gateway SIM, finding the resident by the sender's number; `submit_sos` attaches the resident when the app's copy of an SOS texted from another SIM arrives; inbound texts logged in `sms_log` |
| `migrations/*_ndrrmc_reports.sql` | NDRRMC reports (A5, A6): `ndrrmc_report` (admins only), `report_source()` (the figures for a period: counts only), `save_ndrrmc_report()`, `finalize_ndrrmc_report()`; drafting and finalizing are audited |
| `migrations/*_classifier.sql` | The incident type classifier (FR12): `classifier_model` (the exported model; one is active), `private.classify_report()`, and the trigger that tags each new crowd report before DBSCAN looks at it. Holds the `v1-sample` model, which is trained on made-up descriptions |
| `migrations/*_advisories.sql` | Advisories from the dashboard (D10): `issue_alert()` (dispatchers and admins; an MDRRMD notice or one relayed by hand from PAGASA, PHIVOLCS, or EFCOS; checked, simulated while simulation mode is on, audited) and `end_alert()` |
| `migrations/*_alert_sender.sql` | For the alert sender (service role only): `claim_alert_deliveries()`, `alert_sms_recipients()`, `alert_sms_budget()` (the daily cap `channels.sms_daily_cap`, set on A3), `finish_alert_delivery()` |
| `migrations/*_rescue_confirmations.sql`, `*_rescue_sms_log.sql` | Rescue confirmations (FR6): `rescue_confirmation` (what a resident was told about their own SOS: a unit assigned, on scene, closed), the trigger on `incident_report` that writes them, `mark_rescue_confirmation_read()` for the resident, and for the sender (service role only) `claim_rescue_confirmations()` and `finish_rescue_confirmation()`; the SMS log gets the kind `rescue` |
| `migrations/*_push_notifications.sql` | Push (FR6, FR14): `push_device` (phones' FCM tokens; service role only), `push_message` (the queue of personal pushes; service role only), `register_push_device()` and `forget_push_device()` for the app, triggers that queue a push for each rescue confirmation and each new dispatch, and for the sender `claim_push_messages()`, `finish_push_message()`, `forget_push_tokens()`. Nothing is ever deleted: a phone that signs out or that FCM no longer knows is marked `forgotten_at` |
| `functions/send-alerts/` | Works through queued alert deliveries: texts residents of the affected barangays through Semaphore (one SMS each, up to the daily cap), logs every text in `sms_log`, and records each channel's outcome. Also sends rescue confirmations: one text to the resident whose SOS got a unit. And push through Firebase Cloud Messaging: alerts to topics, rescue confirmations and new assignments to the account's phones (`fcm.ts`). `alerts.test.ts`, `fcm.test.ts`, and `index.test.ts` run with `node --test` |
| `functions/post-incidents/` | Posts each flood, fire, or structural incident on the MDRRMD Facebook Page and edits that same post as it goes (unverified once a unit is sent, then confirmed, false alarm, or resolved): what it is, the district, the time (the words come from the database; migration `incident_posts`). Its own switch on A3, off by default. Uses the Page secrets and the shared secret of `send-alerts`. `index.test.ts` runs with `node --test` |
| `functions/sms-intake/` | Receives texts from the gateway SIM, checks the SAGIP1 format and checksum, files the SOS, and returns the reply for the gateway to send; `sms_intake.test.ts` runs with `node --test` |
| `functions/send-sms/` | The Send SMS hook for sign-in codes (Semaphore, or kept in `sms_log` without it); `sms.test.ts` runs with `node --test` |
| `migrations/*_incident_notices.sql` | `incident_notices(incident)` for dispatchers and admins: what the resident was told about their SOS (each rescue confirmation) with its text and push outcome, for the incident drawer (D4) |
| `migrations/*_barangays_full.sql` | `barangay.psgc_code`, `manila_outline` (the city as one shape), `private.load_barangays(json)`, and the Manila check (FR15) against the outline with 50 m to spare |
| `migrations/*_safe_places.sql` | Safe places (2026-10-19): `safe_place` (signed-in users read the visible ones; staff also the hidden), `safe_places_near(lat, lng, need, limit)` (the nearest places that suit a flood, fire, structural, or medical emergency, leaving out places near a confirmed open flood or fire, without saying where those are), and for admins `save_safe_place()` and `set_safe_place_hidden()` (audited). The rules: `private.safe_kinds()`, `private.safe_min_meters()` |
| `data/` | All 897 barangays: `fetch_barangays.py` (downloads PSA's boundaries, checks them against the PSGC, writes the files), `manila_barangays.json` (what the database loads), `manila_barangays.csv` (name, district, code, center, area) |
| `migrations/*_pagasa_feed.sql` | The PAGASA feed: `feed_status` (dispatchers and admins read it), `record_pagasa_reading()` and `record_feed_status()` (service role only), and a `pg_cron` job that calls `ingest-pagasa` every 10 minutes |
| `functions/ingest-pagasa/` | Reads PAGASA's public pages (FR5): the NCR Heavy Rainfall Warning and the latest Tropical Cyclone Bulletin (PDF), and records Manila's rainfall level, wind signal, and storm surge. `pagasa.test.ts` runs the parsers on saved pages and bulletins with `node --test` |
| `migrations/*_sender_wakeup.sql` | `pg_net` and triggers on `alert_delivery`, `rescue_confirmation`, and `push_message` that call `send-alerts` when something is queued, with a random shared secret kept in Supabase Vault (`sender_secret()`, service role only) |
| `migrations/*_ble_relay.sql` | Tier 3 Bluetooth relay (proof of concept): `relay_sos()` for any signed-in phone that heard an SOS (checked, at most 30 an hour per account, files it as an unverified SOS from an unknown sender until the resident's own copy arrives) and `sos_relay_log` (service role only) |
| `migrations/*_sos_delivery_report.sql` | `sos_delivery_report()` for the Objective 3 trials (admins only; see "Objective 3: SOS delivery report") |
| `migrations/*_simulated_incidents.sql` | `simulate_sos()` and `simulate_crowd_reports()` (admins, simulation mode only, audited), `is_simulated` on incidents and crowd reports, simulated incidents left out of A4, Objective 3, and NDRRMC figures |
| `migrations/*_report_pdfs.sql` | The private `ndrrmc-reports` bucket (admins read; one file per final report, added once) and `attach_report_pdf()` |
| `migrations/*_sms_checks.sql` | Two-way SMS check: `sms_check` (service role only), `send_sms_check()` queues the text, `claim_sms_checks()` and `finish_sms_check()` for the sender, `record_sms_check_reply()` for `sms-intake` |
| `migrations/*_phivolcs_feed.sql` | `phivolcs_event` (dispatchers and admins read it), `record_phivolcs_events()` (service role), and a `pg_cron` job every 15 minutes for `ingest-phivolcs` |
| `functions/ingest-phivolcs/` | Reads PHIVOLCS's earthquake list; `phivolcs.test.ts` runs the parser on a saved page with `node --test` |
| `migrations/20261003130000_forecast_live.sql` | **Not applied yet.** `forecast_model`, `forecast_replay`, `forecast_live_input()` and `record_forecast_run()` (service role), and a `pg_cron` job every six hours for `run-forecast` |
| `functions/run-forecast/` | The forecast's live feed: the LSTM in TypeScript on replayed weather, the provisional rule; `forecast.test.ts` checks it against Keras with `node --test` |
| `migrations/*_river_levels.sql` | `river_level` (dispatchers and admins read it), `record_river_levels()` (service role), `feed_status` source `efcos`, and a `pg_cron` job every 10 minutes for `ingest-efcos` |
| `functions/ingest-efcos/` | Reads PAGASA's river level list for the Pasig, Marikina, and Tullahan rivers; `efcos.test.ts` runs the parser on a saved copy with `node --test`. Deployed (version 2); `intermediate.ts` holds the certificate PAGASA's server leaves out |
| `migrations/*_sos_followups.sql` | Cancel SOS (`request_sos_cancel()`, `withdraw_sos_cancel()`, `confirm_sos_cancel()`) and the resident's newest position while an SOS is open (`update_sos_location()`); the board, `my_sos()`, and `my_assignments()` carry both |
| `migrations/20261011030000_data_retention.sql` | The setting `privacy.retention_months` (6 to 60, 12 by default), `private.apply_retention()`, and a `pg_cron` job every night |
| `migrations/*_report_rag.sql` | `report_reference` (the passages, provisional), `report_rewrite` (the log and the hourly limit), `begin_report_rewrite()`, and `mark_report_rag()` |
| `functions/generate-report/` | The RAG step: finds the passages for each section and asks Gemini to write it from the figures (several keys in turn, Groq after them); `rag.test.ts` runs with `node --test`. Deployed (version 1); answers "not set up" until the keys are added |
| `tests/rls_test.sql` | 465 pgTAP checks of who can see and do what |
| `seed.sql` | Loads the sample data on a local database |

Migration file names match the versions recorded on the hosted project. Never edit an applied migration; add a new file.

## No made-up data on the hosted project (from 2026-10-12)

Joshua asked for everything invented for demos to be removed from the real database: the sample incidents and their records, the sample residents and households, the sample rescue units, the sample forecast run, the classifier trained on invented reports, and the texts, pushes, reports, and audit entries made from them. `*_clear_demo_data.sql` defines `clear_demo_data()`. **Done on 2026-10-12** (applied as `20261012023754` and run by Claude through the connector): it removed 7 incidents, 12 crowd reports, 8 residents, 12 units, 897 forecast rows, and the sample classifier; the temporary emulator account went with them.

Afterwards, and until real data arrives:

- The Command Board is empty until a real SOS, or a simulated one from A3 (simulation mode), comes in.
- **Nothing can be dispatched until units exist:** enter MDRRMD's real units on A2 Resources.
- Reports are not tagged with a type until the classifier trained on the real descriptions is loaded.
- D8 says there is no forecast until the forecast model is retrained and run.
- The Vulnerable Resident Priority List is empty until residents register.

Kept: the staff accounts, the 897 barangays, the settings, what the live feeds read (river levels, PHIVOLCS, PAGASA from its next reading), the Dijkstra timing log, and the provisional reference passages for the report's language model.

**Do not run `reset_demo_data()` by hand any more:** it would put the made-up records back. It stays because the RLS test loads the sample data inside a transaction that is rolled back. The apps' own sample-data mode (running without `.env`) is unchanged: it never touches the database, and the automated tests run on it.

The same goes for `load_sample_classifier()` (2026-10-13): it puts the sample classifier back and makes it active, for the RLS test only. Run by hand it would tag real reports with a model trained on made-up descriptions. The test also sets the channel switches it assumes (Facebook off, push and SMS on) and counts only its own push tokens, so it passes whatever the hosted project is set to: 436 of 436 on the real data on 2026-10-13, and 444 of 444 after `road_hazards()` was added the same day.

`road_hazards()` (2026-10-13) tells a responder's phone where the confirmed open floods and fires are, so its own Dijkstra goes around them: type and position only, never the caller's own incident, staff only.

## Changing the demo data

- **Small edits:** open the Table Editor in the Supabase dashboard and edit rows directly (for example a unit's status or a resident's household). Items with an eye icon are **views** and cannot be edited; change the table they read from:

  | View | Edit instead |
  |---|---|
  | `incident_board` | `incident_report` (the timeline is `incident_event`) |
  | `resident_profile`, `vulnerable_resident_list` | `manila_resident` (name, full number, barangay, consent) and `vulnerable_member` (household members) |

  A resident is on the Vulnerable Resident Priority List only when `consent_given_at` is set and they have at least one `vulnerable_member` row. The dashboard updates live, except for edits to `manila_resident` (not sent over Realtime because it holds full numbers): reload the page after those.
- **Moving an incident through its steps** (assign, en route, on scene, resolved): use the dashboard or `demo_advance()` below, not direct edits, so unit status and incident status stay in step.
- **Start over:** in the SQL editor run `select public.reset_demo_data();`. It wipes incidents, reports, residents, units, alerts, forecasts, completion reports, and the audit log, and reloads the sample data. Staff accounts and barangays are kept. Run it once after the mobile migrations to get the sample alerts, forecasts, and past rescues.
- **Alerts and forecasts:** add rows to `public_alert` (an empty `barangays` list means all of Manila; set `expires_at` to hide one later) and `barangay_forecast` (the newest row per barangay is the current forecast). The dashboard's forecast page (D8) shows one run: the rows that share the newest `issued_at`, so a run of the model must write every barangay with the same `issued_at`. `model_version = 'sample'` marks made-up values and the page says so; a run more than 24 hours old is flagged as overdue.
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
- Refusals come back as short codes the app turns into its own messages: `not_allowed`, `invalid_value`, `not_found`, `incident_closed`, `outside_manila`, `rate_limited`, `no_location`, `account_suspended`, `no_assignment`, `finish_report_first`, `already_on_scene`.

## Turning on resident sign-in by SMS code (for Joshua)

The app asks Supabase to text a code; Supabase hands the code to the `send-sms` Edge Function (a "Send SMS hook"), which sends it through Semaphore. Until the Semaphore account exists, the function sends nothing and keeps the message (with the code) in the `sms_log` table for an hour, so the demo still works.

1. **The function:** deployed by Claude on 2026-10-03 (version 1, JWT check off). Until step 4 it answers "The SMS hook is not set up." To redeploy after a change: `supabase functions deploy send-sms --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`.
2. **Turn on phone sign-in:** Authentication > Sign In / Providers > Phone: enable it. The SMS provider fields can stay empty when the hook is used.
3. **Point the hook at the function:** Authentication > Hooks > Send SMS hook > Add: type HTTPS, URL `https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/send-sms`. Click "Generate secret" and copy it (it starts with `v1,whsec_`).
4. **Give the function its secrets:** Edge Functions > Secrets: `SEND_SMS_HOOK_SECRET` = the secret from step 3. Later, when the account exists: `SEMAPHORE_API_KEY`, and `SEMAPHORE_SENDER_NAME` once Semaphore approves it.
5. **Try it:** in the app, enter a number and tap Send code. Without Semaphore, read the code in the Table Editor: `sms_log`, newest row. With Semaphore, the phone gets a text.
6. **For demos without texts at all:** Authentication > Sign In / Providers > Phone > Test phone numbers: for example `639170004821=123456` (Maria's sample number). Test numbers never call the hook.

The function never logs full numbers (only "0917 ••• 4821"), and `sms_log` is not readable from the apps.

## Free SMS: the gateway phone instead of Semaphore

Semaphore charges per text. The free route is the gateway phone itself: **SMS Gateway for Android** (free and open source, by capcom6, on Google Play and GitHub) turns a spare Android phone with a prepaid SIM into an SMS gateway. The SIM's own load pays for the texts, and an unlimited-text promo from the network (for example a weekly unli-text add-on) keeps the cost to a few pesos for a whole demo or trial. The same phone also receives the SOS texts (Tier 2 below), so one phone does both directions.

With the three secrets below set, every text goes from the gateway SIM: sign-in codes (`send-sms`), alert broadcasts, rescue confirmations, and SMS checks (`send-alerts`), and the replies to SOS texts (`sms-intake`). Semaphore stays as the fallback when they are not set. All three functions are deployed with this (2026-10-03).

1. Install SMS Gateway for Android on the spare phone, sign in to its **cloud server** mode (Settings, Cloud server), and note the username and password it shows. Allow it to send and receive SMS and to run in the background (battery: unrestricted).
2. Edge Functions > Secrets: `SMS_GATEWAY_SEND_URL` = `https://api.sms-gate.app/3rdparty/v1/messages`, `SMS_GATEWAY_USERNAME`, `SMS_GATEWAY_PASSWORD`.
3. Check it: the check in "Sending alerts by SMS" step 2 now says `gateway: set: texts go from the gateway phone`.
4. Limits to know: Android asks for confirmation after many texts in a short time (the app has a setting to space them out), networks may block a SIM that sends thousands of identical texts a day, and each text takes a second or two. The A3 "SMS alert limit" (500 a day by default) protects the SIM; for the capstone's numbers (a pilot barangay, UAT) this is enough. A city-wide rollout would go back to a paid bulk sender.

## Tier 2: SOS by SMS (for Joshua, when the gateway SIM exists)

When a phone has signal but no data, the app texts the SOS to the MDRRMD gateway SIM in a short checked format (`SAGIP1 SOS <id> <lat>,<lng> <accuracy> <time> <flags> <crc>`). The gateway forwards each text to `sms-intake`, which files the SOS; the app's later internet copy is recognised by the same id.

1. **Gateway phone:** a spare Android phone with the gateway SIM, running an SMS gateway app that forwards received texts to a webhook (for example SMS Gateway for Android). Set its webhook to `https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/sms-intake` with the header `x-sagip-key: <secret>`.
2. **The function:** deployed by Claude on 2026-10-03 (version 1, JWT check off). Until step 3 it answers `sms-intake is not set up` and files nothing. To redeploy after a change: `supabase functions deploy sms-intake --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`.
3. **Secrets:** `SMS_INTAKE_SECRET` = the same secret (make one with at least 32 random characters, for example from a password manager; it never goes in the repo). **The reply from the gateway SIM** (version 2, deployed 2026-10-03): in SMS Gateway for Android turn on cloud mode, then add `SMS_GATEWAY_SEND_URL` = `https://api.sms-gate.app/3rdparty/v1/messages` and the app's `SMS_GATEWAY_USERNAME` and `SMS_GATEWAY_PASSWORD` (shown in the app). The function then asks the phone to text "Your SOS was received (INC-..., ref xxxxxxxx)" back from the SIM (the ref is the first 8 characters of the SOS id; the app reads this reply to know the text arrived and stops asking nearby phones, 2026-10-19), logged in `sms_log` (`kind = 'ack'`, `provider = 'gateway'`). The app's local mode cannot be used: Supabase cannot reach a phone on your Wi-Fi. Without those secrets, `SMS_ACK_VIA_SEMAPHORE=true` sends the reply through Semaphore; with neither, the response's `reply` is for the gateway to send.
4. **Phones:** an admin enters the gateway SIM's number on the dashboard's Configuration page ("Numbers shown in the apps"). Phones read it when the app starts and keep the last copy, so it is there with no data. No rebuild is needed; `SMS_GATEWAY_NUMBER` in `apps/mobile/.env` still works and takes priority. Residents allow SMS on the welcome screen.
5. **Try it:** turn off mobile data on a test phone (keep signal), hold SOS; the board shows it as an SMS SOS within seconds. Unreadable texts are in `sms_log` (`kind = 'inbound'`, `status = 'unreadable'`).

## The resident web form (W1 to W3)

Residents who have not installed the app can send a hazard report from a browser (FR15). It is a second entry point of the dashboard package, deployed to its own address:

```bash
cd apps/dashboard
flutter run -d chrome -t lib/main_webform.dart                                # on sample data
flutter run -d chrome -t lib/main_webform.dart --dart-define-from-file=.env  # on this project
flutter build web --release -t lib/main_webform.dart -o build/webform --dart-define-from-file=.env
```

- **Sign-in** is the app's: a mobile number and a texted code, so it needs the Send SMS hook above. A new number can create an account on the form (plan Q13 is not decided; build with `WEBFORM_REGISTRATION=false` to allow sign-in only). The form keeps its own saved session (`sagip-webform-auth`), apart from the dashboard's.
- **Reports** go through `submit_crowd_report` with `p_source => 'webForm'`, so the Manila check, the hourly limit, the suspension check, and DBSCAN all apply. A report is never confirmed on its own. The form cannot send an SOS; every page says so and gives the hotline (the one set on the Configuration page, or `MDRRMD_HOTLINE` at build time) and, when set, the app link (`APP_DOWNLOAD_URL`).
- **The hourly limit** is `reports.per_hour` in `app_setting` (5 by default, 1 to 30), set on the dashboard's Configuration page. It counts a resident's reports from the app and the web form together; the server also refuses more than twice the limit received in an hour, whatever their capture times.
- **The draft** (description, type, location) stays in the browser's local storage until the report is sent or the resident signs out. The server never sees it before Send.

## Alerts: thresholds, channels, and simulation mode

- **Thresholds.** `app_setting` holds a warning and a critical value for rainfall (mm per hour), the wind signal, and storm surge height (m). They are provisional (PAGASA's rainfall warning levels and storm surge risk bands) until MDRRMD confirms them; an admin changes them on the Configuration page.
- **The engine.** Each new row in `weather_alert` is compared with the reading before it. When a hazard's level changes, the earlier automatic alerts for that hazard expire and, at warning or critical, a new row goes into `public_alert` (residents see it in the app at once). A reading at the same level raises nothing; the very first reading only sets the baseline. This is what the PAGASA feed will drive once it exists: it only has to insert readings.
- **Deliveries.** Every new alert gets four rows in `alert_delivery`: `app` (sent), and `push`, `sms`, `facebook` as `queued`, or `off` when the channel is switched off on the Configuration page. The `send-alerts` Edge Function works through the queued rows (steps below); until it is deployed they stay queued. The Weather page shows the log.
- **Simulation mode.** With the switch on (Configuration page), an admin can send a simulated reading (`simulate_weather`): a typhoon, heavy rain, or calm. The engine treats it like any reading, but the alerts are marked simulated and their deliveries are `simulated`: shown in the apps, never texted or posted. From the SQL editor a real-looking reading is `insert into public.weather_alert (signal_level, rainfall_intensity, storm_surge_m) values (3, 35, 2.5);` (that one queues real deliveries).
- **The numbers.** `contact.hotline` and `contact.sms_gateway` are the hotline and the gateway SIM the apps show and use. `client_config()` returns them and can be called without signing in (they are public numbers).
- **Advisories by hand.** On the Weather page, "Issue an advisory" calls `issue_alert()`: the dispatcher picks who it is from (MDRRMD, or a PAGASA, PHIVOLCS, or EFCOS notice being passed on), the level, the text, up to 8 "what to do" steps, and all of Manila or chosen barangays, then reviews it before sending. It goes out like any other alert (the deliveries above). "End alert" calls `end_alert()`: the apps stop showing it, it stays in the log, and anything still queued for it is not sent.
- **Not done:** the data retention period (which records are removed and when is a decision for the team and MDRRMD) and EFCOS levels. Push works (Firebase `sagip-a4b9e`). Facebook posting is written (below) and waits on the Page token.

## Sending alerts by SMS (for Joshua, when the Semaphore account exists)

`send-alerts` texts each queued alert to the registered residents of its barangays (everyone for an all-Manila alert): one SMS per resident, cut to 160 characters, never more than the daily cap an admin sets on the Configuration page ("SMS alert limit", 500 by default). Each text is logged in `sms_log`; the delivery row on the Weather page gets the counts, and says so when the cap left some unsent. Simulated alerts are never sent.

`send-alerts` is deployed (2026-10-03, JWT check off: it checks its own shared secret). The database calls it by itself whenever something is queued (migration `sender_wakeup`: triggers on `alert_delivery`, `rescue_confirmation`, and `push_message` call it through `pg_net`, with a random shared secret kept in Supabase Vault). No Database Webhook and no `ALERTS_SECRET` are needed. To redeploy after a change: `supabase functions deploy send-alerts --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`.

1. **Secrets** (Edge Functions > Secrets, the page with a list of names and values; not "Deploy a new function"): `SEMAPHORE_API_KEY`, and `SEMAPHORE_SENDER_NAME` once Semaphore approves it. Without the Semaphore key the function marks SMS deliveries "not set up" and sends nothing.
2. **Check it:** in the SQL editor run

   ```sql
   select net.http_post(
     url := 'https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/send-alerts',
     body := '{"check": true}'::jsonb,
     headers := jsonb_build_object('Content-Type', 'application/json', 'x-sagip-key', public.sender_secret()));
   ```

   then, a few seconds later, `select status_code, content::text from net._http_response order by id desc limit 1;`. It says whether Firebase signs in, whether the Semaphore key is set, and sends nothing.
3. **Try it:** with simulation mode off, insert a reading that crosses a threshold (see the SQL above), or wait for the PAGASA feed. Check the Weather page's alert log and `sms_log`.

Not checked against the real Semaphore API (no account yet): the function assumes its messages endpoint answers with one entry per recipient. Send one test alert to a barangay with only your own number before the pilot.

## Rescue confirmations (FR6)

A resident is told about their own SOS as the rescue moves on. A trigger on `incident_report` writes a row in `rescue_confirmation` each time:

| Kind | When | In the app | By SMS |
|---|---|---|---|
| `assigned` | A unit is assigned, or changed | Yes | The first one of each SOS only |
| `onScene` | The unit arrives | Yes | No |
| `resolved` | The SOS is closed | Yes | No |

- **Who.** Only an SOS with a registered resident. A crowd-report cluster has no single sender, and an SOS marked as a false report gets no closing confirmation. An SOS texted from an unknown SIM gets its "assigned" confirmation when the app's copy names the resident, if a unit is already on the way.
- **In the app.** The resident's Alerts tab lists them above the public alerts (the last 7 days), each with the unit's call sign and the incident number; a new one is also said on whatever screen is open. Residents read only their own rows; dispatchers and admins can read all of them; `mark_rescue_confirmation_read()` marks one read.
- **By SMS.** `sms_status` on the row says what happened to the text: `queued`, `sending`, `sent`, `failed`, `off` (the SMS channel was switched off on the Configuration page), `simulated` (simulation mode was on), `notSetUp` (no Semaphore key), `expired` (still waiting after 30 minutes, so not sent), or `none` (this kind is not texted). These texts are not counted against the daily cap on alert texts: there is one per SOS.
- **Sending.** `send-alerts` sends them, before any alert; the database calls it when one is queued. Without the Semaphore key they are marked `notSetUp`.
- **Before texting for real:** the demo residents' numbers are made up and may belong to someone. Keep simulation mode on while the demo data is loaded, or reload real residents first.
- **Not done:** push (needs the Firebase project). **To confirm with MDRRMD:** which steps are texted, and the wording (English for now): "S.A.G.I.P.: Rescue team R-03 has been sent to your location. Stay where you are if it is safe and keep your phone on. Ref INC-0152."

## Push notifications (FR6, FR14; for Joshua: the Firebase project)

The thesis promises "in-app push notifications" for alerts, advisories, and rescue confirmations (FR6, FR14, Process 4.0). On Android that means Firebase Cloud Messaging (FCM), which is free. Everything is built and tested; what is missing is the Firebase project, which needs your Google account.

**What gets pushed**

| Push | To whom | How |
|---|---|---|
| A weather alert or advisory (not simulated) | Residents of its barangays, or everyone for all of Manila; responders get the all-Manila ones | FCM topics: each phone joins `manila` and `area-<barangay>` (for example `area-barangay-412`) at sign-in |
| A rescue confirmation (unit assigned, on scene, SOS closed) | The resident's phones | `push_message`, written by a trigger on `rescue_confirmation` |
| A new assignment | The phones of the responders on that unit | `push_message`, written by a trigger on `dispatch` |

The A3 switch "Send alerts as push notifications" (`channels.push`) turns all three off; a push made while it is off is logged as `off`. Simulated alerts are never pushed (as with SMS); rescue confirmations and assignments are, in simulation mode too, because they go only to people already using the app. A push waiting over 30 minutes is not sent. Tapping a notification opens the alert, the SOS, or the responder's home.

**Setting it up (about 15 minutes)**

1. **Create the project:** https://console.firebase.google.com, Add project, name it `sagip`. Google Analytics is not needed (turn it off).
2. **Add the Android app:** in the project, Add app, Android. Package name `ph.sagip.sagip_mobile` (exactly). Skip the SHA-1 and the SDK steps. Download `google-services.json` and put it in `apps/mobile/android/app/`. It is git-ignored: do not commit it (the repo is public). The build picks it up by itself; without it the app builds and runs with push off.
3. **The sender's key:** Project settings, Service accounts, Generate new private key. A JSON file downloads. In Supabase open **Edge Functions, then Secrets** (a list of names and values; do not use "Deploy a new function"), add a secret named `FIREBASE_SERVICE_ACCOUNT`, and paste the whole file as its value. Then delete the downloaded file; never put it in the repo or in the app.
4. **Check it:** run the check in "Sending alerts by SMS" step 2. It should say `ready: signed in to project <your project id>`. Other answers: `FIREBASE_SERVICE_ACCOUNT is not set` (the secret is missing or has another name), `... is not a Firebase service account key file` (only part of the file was pasted), `Firebase sign-in refused` (the key was deleted or disabled in Firebase). The function is already deployed and the database calls it by itself.
5. **Try it:** build and install the app with `.env`, sign in as a resident on a phone or the emulator (with Google Play), send an SOS, and assign it a unit on the dashboard: the phone gets "A rescue team is coming" even with the app closed. In the SQL editor, `select status, devices, delivered, detail from public.push_message order by message_id desc limit 5;` shows what happened.

**Privacy:** tokens identify an install, not a person; only the service role reads them. FCM sees the topic names (barangay level) and the notification text. A phone's row stays after sign-out, marked `forgotten_at`; how long such rows are kept belongs to the data retention rule that is still to be decided.

## Posting alerts on the MDRRMD Facebook Page (for Joshua, when MDRRMD gives access)

`send-alerts` posts each queued `facebook` delivery on the Page through the Graph API (`POST /{page-id}/feed`): the level, the title, the text, the affected barangays (or "All of Manila"), and a line on how to ask for rescue. The delivery row gets the post id, or Facebook's reason when it refuses (an expired token, for example). Simulated alerts are never posted. The channel is off by default on the Configuration page.

The code is in the repo with tests (`node --test supabase/functions/send-alerts/*.test.ts`), and the deployed copy has it (version 5; its check answered `facebook: FACEBOOK_PAGE_ID or FACEBOOK_PAGE_TOKEN is not set` on 2026-10-13). Only the two secrets and the switch on the Configuration page are missing; step 3 below is not needed.

1. **Access:** a Page admin at MDRRMD makes a Meta app (developers.facebook.com, type Business), adds the Page, and creates a long-lived **Page** access token that may post (`pages_manage_posts`, `pages_read_engagement`). For the capstone a test Page you own works the same way.
2. **Secrets** (Edge Functions > Secrets): `FACEBOOK_PAGE_ID`, `FACEBOOK_PAGE_TOKEN`. Optional `FACEBOOK_GRAPH_VERSION` (default `v24.0`).
3. **Redeploy:** `supabase functions deploy send-alerts --no-verify-jwt --project-ref imssgenjfirpohkwxwbv` (or ask Claude).
4. **Check:** the check in "Sending alerts by SMS" step 2 now also says `facebook: page and token set`.
5. **Switch it on:** Configuration page, "Post alerts on the MDRRMD Facebook Page". Issue a test advisory to a test Page first.

The token is a secret: it is sent only in the request body to Facebook and is never logged.

## Two-way SMS check (migration `sms_checks`)

"Send SMS check" in the D4 drawer now texts the SOS sender (the resident's number, or the number an SMS SOS came from): "MDRRMD got an SOS from this number (INC-0147). Reply YES if you need rescue, or NO if it was a mistake." `send-alerts` sends it (gateway SIM or Semaphore). When `sms-intake` receives YES (Y, OO, OPO) or NO (N, HINDI) from that number within two hours, `record_sms_check_reply()` adds the answer to the incident's timeline, the drawer shows it, and the sender is thanked. The dispatcher still decides. `sms_check` holds full numbers and is service-role only.

## PHIVOLCS earthquakes (migration `phivolcs_feed`, FR14)

`ingest-phivolcs` reads PHIVOLCS's public earthquake list (earthquake.phivolcs.dost.gov.ph, about 120 KB compressed) every 15 minutes and keeps the events within 300 km of Manila from the last 48 hours in `phivolcs_event` (dispatchers and admins read it). The Weather page lists those of magnitude 3 and up within 200 km (provisional) with "Relay as advisory", which opens the advisory dialog filled in (source PHIVOLCS, level info, title, text, three safety steps) for the dispatcher to check and send. Nothing reaches residents by itself: earthquakes are relayed, never forecast. The feed's health is the third line of the feeds card (`feed_status`, source `phivolcs`). Deployed and running since 2026-10-03; the first run kept 42 events.

## Simulated incidents for demos (migration `simulated_incidents`)

With simulation mode on (Configuration page), an admin can make a **simulated SOS** (optionally with a senior citizen in the household) or **three simulated crowd reports** of a chosen type in any barangay. They go through the same triggers as real ones: the classifier tags the reports and DBSCAN turns the three into one confirmed incident within seconds. They show on the board with a "Simulated" tag and can be verified, assigned, and resolved like any incident, so the whole SOS-to-resolved flow can be shown without a resident phone. `is_simulated` marks them; A4 analytics, the Objective 3 report, and NDRRMC report figures leave them out. Each one is in the audit log (`sosSimulated`, `reportsSimulated`).

## Final NDRRMC report PDFs (migration `report_pdfs`)

When an admin marks a report final (A6), the dashboard builds its PDF and keeps it in the private Storage bucket `ndrrmc-reports` as `<report id>.pdf`; `attach_report_pdf()` records it on the report. Only active admins can read the bucket, a file can be added only for a final report and only once, and there is no update or delete, so the stored copy stays as issued. "Download PDF" on a final report gives the stored copy. If storing fails (no connection), the report is still final and "Store the PDF" tries again.

## The forecast's live feed (migration `forecast_live`, **not applied yet**)

`run-forecast` makes a forecast run every six hours without TensorFlow: `ml/forecast/export_live.py` writes `supabase/data/forecast_live_v1.json` (the three LSTMs' weights and scalers, three years of replayed sample weather, the KDE density per barangay, the provisional rule), and the function runs the same LSTM in TypeScript (its tests match Keras's own output to 0.00001), moving one replayed day per run. Rows are marked simulated and say which day was replayed (D8 shows it). To switch it on: Joshua approved on 2026-10-03, but the Supabase connector declined the migration every time it was tried (it creates tables and a `pg_cron` job), so paste the file into the SQL editor yourself:

1. Apply `supabase/migrations/20261003130000_forecast_live.sql` (rename it to the version `list_migrations` gives).
2. The function: deployed by Claude on 2026-10-03 (version 1); it does nothing until the migration and the model are there.
3. Load the model once the file is on GitHub (pinned commit), in the SQL editor:

   ```sql
   select net.http_get('https://raw.githubusercontent.com/angrypoteto/project-sagip/<commit>/supabase/data/forecast_live_v1.json');
   -- a few seconds later, with the id it returned:
   select private.load_forecast_model(content::jsonb) from net._http_response where id = <id>;
   ```

4. First run without waiting: `select private.call_run_forecast();`

## The migrations of 2026-10-11

Three are applied (2026-10-11, through the connector once it came back): `river_levels`, `sos_followups`, and `report_rag`. Both new functions are deployed, and the river feed runs (17 stations on its first read).

`20261011030000_data_retention.sql` was declined by the connector (it contains `delete` statements) and run by Joshua in the SQL editor instead, so it has no row in the migrations table and keeps its file name. The RLS test then ran in full: 410 of 410 (`9a1b210`).

## River levels (migration `river_levels`, FR5)

EFCOS itself has no public feed. PAGASA's server sends its certificate without the intermediate one, which the function carries in `intermediate.ts` (valid to June 2029; if the feed fails with "invalid peer certificate", PAGASA changed it: replace the file). PAGASA publishes the levels of the same rivers (its Pasig-Marikina-Tullahan flood forecasting and warning system) as JSON, with each station's own alert, alarm, and critical level: `https://pasig-marikina-tullahanffws.pagasa.dost.gov.ph/water/main_list.do`. `ingest-efcos` reads it every 10 minutes and keeps each station's newest reading. D10 lists the stations, raised ones first; "Relay as advisory" fills in an advisory with source EFCOS for the dispatcher to review. Nothing is sent to residents by itself: on the day the list was saved, one station (Ugong) read above its critical level while its neighbours were normal, which is what a faulty sensor looks like. The thesis should say the levels come from PAGASA's stations on the rivers EFCOS watches, not from EFCOS.

## Cancel SOS and the newest position (migration `sos_followups`; plan Q10, Q33)

A resident may ask to cancel their own SOS until the unit is on scene, with a reason (safe now, sent by mistake, another reason). The SOS stays open and on the board, marked "Asked to cancel"; a dispatcher closes it with "Close as cancelled" (audited as `sosCancelled`) or carries on, and the resident may take the request back. Asking needs internet: it is never queued, because a cancel that arrives hours late could close an SOS the resident needs again.

While an SOS is open and the app is on, the phone sends its position when it has moved 25 m or more, at most once a minute (the server keeps at most one every 20 seconds, inside Manila only). The place the SOS was sent from never changes; the newest position is kept beside it, the board and the unit suggestions use it, and the assigned responder is routed to it.

## Data retention (migration `data_retention`; RA 10173)

An administrator sets the period on A3 (6 to 60 months, 12 by default; provisional until MDRRMD confirms it). Every night at 03:15, incidents closed for longer than that lose the link to the resident, the note, the address, the position the phone sent, and what the resident was told; the exact position is rounded to three decimals (about 110 m, the forecast's grid cell, so the KDE training data and the barangay counts hold). Old crowd reports lose the link and the exact position; their text is kept for the classifier. The texts log is emptied of older rows. The incident itself, its timeline, the dispatch and completion records, and the audit log stay. Each run is audited as "System" (`retentionApplied`). To see what a run would do, an admin can count: `select count(*) from incident_report where status = 'resolved' and anonymized_at is null and resolved_at < now() - interval '12 months';`.

## Unit inventory and the real stations (migration `unit_inventory`, applied as `20261012041940`)

Each unit's crew reports what it carries with `set_unit_supply(item, quantity, capacity)`: `fuel` and `tankWater` as a percent, `drinkingWater`, `medicalKits`, `lifeVests`, and `rescueGear` as a count against a full load (remembered after the first report). Only a responder, only for the unit they are on; dispatchers and admins read `unit_supply`, nobody writes it directly; each report is audited as `supplyUpdated`. A supply is low at or below `inventory.low_percent` (A3, 30 by default) and out at zero.

`response_unit` has `agency` (`mdrrmd`, `bfp`, `volunteer`, `ems`) and `source`, a `fireTruck` type, and `crew_size` may be empty. `supabase/data/manila_units.sql` holds the ten real stations loaded on 2026-10-12 (OpenStreetMap; the file says what was assigned by us). It can be run again; it never changes an existing row. Do not run `clear_demo_data()` again: it would remove these units too.

## A unit's station and its crew's position (migrations `unit_home`, `unit_ghost`)

`response_unit.home_latitude/home_longitude` is the station; `last_latitude/last_longitude/last_location_at` is only what the crew's phone reported (`update_unit_location`, at any time, not only on a job). The dashboard draws a free unit at its station with a faint marker for its crew (a fix under 10 minutes old), and a unit on a job at its crew's position with a faint marker for the station. An admin sets the station on A2 (`set_unit_home(unit, latitude, longitude)`; both empty clears it). `private.unit_returns_home()` is a leftover that does nothing: `drop function private.unit_returns_home();` in the SQL editor removes it.

## The RAG step of the NDRRMC report (migration `report_rag`; for Joshua: the Gemini key)

On A6, "Rewrite with the language model" sends the draft's figures and its assembled sections to `generate-report`. For each section the function finds the three closest reference passages in `report_reference` (by embedding; by shared words if embeddings fail), and asks Google Gemini to write the section from the figures, following the passages. The new text goes into the editor unsaved, with the passages used and a list of any numbers that are in none of the figures; "Put the earlier text back" undoes it. A draft saved after a rewrite is marked `rag` (`mark_report_rag()`).

- What is sent to Google: counts, barangay names, and times. No names, numbers, addresses, or coordinates (`report_source()` never had them).
- The twelve passages are provisional, written from the outline of a situation report. Replace them with the NDRRMC template and sample reports when MDRRMD sends them (`delete` and `insert` on `report_reference` in the SQL editor; embeddings are made again by themselves).
- Admins only, 20 rewrites an hour each (`report_rewrite` keeps when, how long, and whether it worked, for Objective 4).

To switch it on, add two Edge Function secrets (Supabase dashboard, Edge Functions, Secrets). **Keys go only there: never in the repo, a `.env` that is committed, or a chat.**

1. `GEMINI_API_KEYS`: the Gemini keys from Google AI Studio, separated by commas (one is enough). Each rewrite starts at a different key; a key that is refused or over its limit is skipped and the next is tried.
2. `GROQ_API_KEYS` (optional): Groq keys, separated by commas. Used only when every Gemini key has failed. Groq's model (`openai/gpt-oss-120b`) follows the rules less closely: in a trial it wrote numbers as words, which the check on numbers cannot read, so its drafts need a slower read.
3. Optional: `GEMINI_MODEL` (default `gemini-3.8-flash`), `GEMINI_EMBEDDING_MODEL` (default `gemini-embedding-001`), `GROQ_MODEL`.

Without any key the button says the language model is not set up, and the assembled draft is unchanged.

Tried on 2026-10-11 from Claude's machine with the function's own prompt and checks (six sections of sample figures): Gemini answered in about 19 seconds with every number kept and none added; Groq in about 3 seconds. The embedding call returned 768 numbers as expected. **Not yet tried:** the deployed function end to end from A6 (it needs the secrets).

## Objective 3: SOS delivery report

`sos_delivery_report(from, to)` (admins only) counts the SOS received in a period by the tier that delivered them first (app, SMS, Bluetooth relay), with the delay from the phone's capture time to the server's receipt: median, 95th percentile, longest, and how many arrived within 1, 5, and 15 minutes. It also reads `sos_relay_log`: relayed packets uploaded, for how many SOS, and the most hops. The dashboard's Analytics page shows it as "SOS delivery (Objective 3)"; the trial team types in how many attempts they made on the phones and the page shows the success rate for each window. Which window counts as a success is plan Q44. The page's periods are the last 24 hours, 7 days, and 30 days, so count the SOS already in the period before the trial starts and subtract them, or run the trial on a project without demo SOS.

## Incident type classifier (FR12)

Every new crowd report is tagged with an incident type from its description, inside the database, before DBSCAN groups reports (thesis Process 2.0). The tag goes in `crowd_report.category` with its probability in `category_confidence`; what the resident chose stays in `reported_type`. A cluster takes the most common tag of its reports as the incident's suggested type, which the dispatcher confirms or changes.

- **The model** is TF-IDF over words and word pairs with logistic regression, trained and exported by `ml/classifier/train_classifier.py` (see `ml/README.md`). It lives in `classifier_model` as one JSON document; the row with `is_active` is the one used.
- **The model loaded now is `v1-sample`: trained on made-up descriptions, not MDRRMD records.** It is there so the whole path works. Do not report its accuracy.
- **When the model is not sure** (below `min_confidence`, 0.5 in `v1-sample`) the report is left untagged and the cluster uses the resident's own choice, if there is one. Text with no known words always lands here.
- **With no active model** reports are stored untagged; nothing is refused.
- **Loading a retrained model:** run the training script, then add a new migration that inserts the new row (the script writes the `insert` to `ml/classifier/build/classifier_model.sql`) and moves `is_active` to it. Reports already stored keep the tag they got.
- **Try it** in the SQL editor: `select * from private.classify_report('Baha na po dito, hanggang bewang ang tubig');`

The same arithmetic runs in Dart (`IncidentClassifier` in `packages/shared`) for the sample-data apps. Both are checked against the same 38 cases (`packages/shared/test/fixtures/classifier_reference.json`).

## NDRRMC reports (A5, A6)

An administrator makes a post-disaster report on the dashboard in three steps: choose a period, let the system collect the records, then review and edit the draft before saving it or marking it final.

- **The figures** come from `report_source(from, to)`: incidents received in the period by type and barangay, how many are resolved, open, or false, what responders reported (persons assisted, injured, missing, affected families, houses damaged, outcomes), dispatches and units, median times to assignment and to arrival, alerts issued, and the highest PAGASA readings. **Counts only: no names, phone numbers, addresses, or coordinates** (RA 10173). Admins only.
- **The draft** is put together from those figures with fixed wording by `draftReportSections()` in `packages/shared` (`method = 'assembled'`). No language model is involved yet: the RAG engine (plan 10.6) will later write the text from the same figures (`method = 'rag'`), and nothing else in the flow changes.
- **The sections are a provisional outline** (situation overview, incidents reported, affected population and casualties, damage to houses, response actions, remarks and recommendations). Replace it with the NDRRMC template when MDRRMD sends it (thesis Table 3.1 item 5): `ReportSections` and `draftReportSections()` in `packages/shared/lib/src/algorithms/report_draft.dart`.
- **A saved draft keeps its figures** as they were when it was made (`source`); editing changes only the text. **A final report cannot be changed.** Both steps are in the audit log.
- **The checklist** on the review step flags what makes a report incomplete: incidents still open, resolved incidents with no completion report, simulated alerts or readings in the figures, an empty section.
- **`generation_ms`** records how long collecting and drafting took, for the Objective 4 time comparison (the manual baseline still has to be measured, plan Q41).
- **The PDF** is made in the browser (the Dart `pdf` package) and downloaded; it is not stored. A Storage bucket for the files is not set up.

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

## The PAGASA feed (FR5)

PAGASA gives no public API in time (plan Q35), so `ingest-pagasa` reads what PAGASA publishes (Joshua's decision, 2026-10-03; plan in `docs/PAGASA-PARSER-PLAN.md`):

- **Rainfall:** the Heavy Rainfall Warning on the NCR page (`bagong.pagasa.dost.gov.ph/regional-forecast/ncrprsd`). The level over Metro Manila becomes its lower bound in mm/hr: Yellow 7.5, Orange 15, Red 30. With today's A3 thresholds (15 and 30), Orange raises a warning and Red a critical alert.
- **Wind signal and storm surge:** the latest Tropical Cyclone Bulletin (a PDF linked from the bulletin page). The highest Wind Signal that names Metro Manila (a "portion of Metro Manila" counts only when its list names Manila), and the highest storm surge height given for coasts that include Metro Manila.

**How it runs.** A `pg_cron` job calls the function every 10 minutes with the shared secret (the same vault secret as `send-alerts`). The database adds a `weather_alert` row only when a value changed (or the current row is simulated), and the threshold engine raises or ends alerts. A page that cannot be read keeps the last value and is counted in `feed_status`, which D10 shows ("PAGASA feed"); dispatchers then relay by hand with "Issue an advisory". **While simulation mode is on, readings are not recorded**, so a demo keeps its simulated weather.

**Real alerts.** With simulation mode off, a real PAGASA warning raises real alerts: shown in the apps and pushed to phones (push works), and texted once Semaphore is set up.

**Check it** in the SQL editor: `select source, ok, checked_at, last_error, seen from public.feed_status;` and `select * from cron.job_run_details order by start_time desc limit 5;`. Run it once now: `select private.call_ingest_pagasa();`. To stop it: `select cron.unschedule('ingest-pagasa');`.

**Redeploy:** `supabase functions deploy ingest-pagasa --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`. Deployed 2026-10-03 (version 1).

## Loading all 897 barangays

**Where the data comes from.** `data/fetch_barangays.py` downloads the barangay boundaries the Philippine Statistics Authority (PSA) publishes through GeoRiskPH (PSA calls them indicative boundaries; they were made for the 2015 census) and checks every name and 10-digit code against the official PSGC list. It stops if anything differs. Manila has 897 barangays in 14 districts (PSA's sub-municipalities; "Tondo I / II" is written "Tondo"). The layer also has two areas that are in no barangay, Tutuban Mall (claimed by five Tondo barangays) and Manila North Cemetery: they count as Manila but are not barangays. Credit: Philippine Statistics Authority. Run it again with `python supabase/data/fetch_barangays.py` (standard library only); it rewrites the JSON, the CSV, and the apps' bundled copy (`packages/shared/lib/src/data/manila_barangays_data.dart`).

**Loading it.** `private.load_barangays(json)` adds the barangays that are missing and updates the rest (district, code, center, boundary). It never removes a name, since residents, reports, and forecasts refer to barangays by name. It also replaces `manila_outline`, and from then on the Manila check for SOS and reports uses that outline (within 50 m). The file is too big to paste, so the database fetches it from GitHub once the commit is pushed. In the SQL editor:

```sql
select net.http_get('https://raw.githubusercontent.com/angrypoteto/project-sagip/main/supabase/data/manila_barangays.json');
-- a few seconds later, with the id the first line returned:
select private.load_barangays(content::jsonb) from net._http_response where id = <id> and status_code = 200;
select count(*), count(boundary), count(psgc_code) from public.barangay;   -- 897 or more, 897, 897
```

The 10 sample barangays keep their names; their centers move to the real ones. The demo records keep their made-up coordinates, so some lie in a different barangay than their label says (Barangay 412's sample SOS is really in Barangay 460).

## Safe places (migration `safe_places`, applied as `20261018230454`)

The nearest place that suits the emergency (Joshua, 2026-10-19), in place of the "nearest evacuation center" dropped on 2026-10-11. The rules are provisional, for MDRRMD to confirm: a flood points to somewhere high (an evacuation center, a school, a barangay or city hall, a covered court; never open ground); a fire to open ground at least 300 m away (an evacuation center, a basketball or covered court, a park or plaza, a school ground); a collapse to open ground at least 100 m away (an evacuation center, a basketball court, a park or plaza); a medical emergency to a hospital. Any place within 150 m of a confirmed open flood or 300 m of a confirmed open fire is left out. The same rules are in `packages/shared/lib/src/models/safe_place.dart`, which the phone uses offline on its bundled list.

**Where the places come from.** `data/fetch_safe_places.py` reads OpenStreetMap through Overpass (schools, colleges, town halls, sports centres, basketball pitches, parks, squares, assembly points, hospitals), keeps those inside one of the 897 barangays (and not marked private), tags each with its barangay, and keeps a place mapped twice once. Sports centres that are businesses (only billiards, bowling, badminton, fitness and the like, a members' club, a cockpit) are left out. On 2026-10-19: 750 places (321 schools, 167 halls, 113 parks and plazas, 88 basketball courts, 22 covered courts and gyms, 39 hospitals). It writes `data/manila_safe_places.sql` and the apps' copy `packages/shared/lib/src/data/manila_safe_places_data.dart`. MDRRMD's own evacuation centers are not public: an admin adds them on the dashboard's Safe places page, marked official. No capacity or occupancy is kept: evacuation center management is out of scope.

**Loading it.** The file is too big to paste, so the database fetches it from GitHub once the commit is pushed. In the SQL editor:

```sql
select net.http_get('https://raw.githubusercontent.com/angrypoteto/project-sagip/main/supabase/data/manila_safe_places.sql');
-- a few seconds later, with the id the first line returned:
do $$ begin execute (select content from net._http_response where id = <id> and status_code = 200); end $$;
select count(*), count(*) filter (where hidden_at is null) from public.safe_place;   -- 763 rows, 750 visible (13 dropped from the first list are hidden)
```

It can be run again: it refreshes the map's own fields of rows no admin has changed (`updated_by` is empty) and never touches what an admin hid, renamed, or added.

## Relayed SOS name their sender (migrations `relay_sender`, `relay_device_keys`, 2026-10-19)

Each resident's phone makes a 32-byte secret per account and hands it over once (`register_relay_key`, at most five phones a resident; no app can read `relay_device`). The phone's SOS ids are HMAC-SHA256 codes of the SOS's capture time, place (the Bluetooth packet's offsets), and mock flag, shaped as version 4 UUIDs (`relaySosId` in `packages/shared` sos_relay.dart; `private.relay_code` here). `relay_sos()` finds the phone whose key makes the id (`private.relay_device_for`), attaches that resident with their consented household, and marks the account verified; the SOS stays Pending Verification. Relaying phones see an id that changes every time and names no one; a changed packet arrives from an unknown sender. The first try of the same day, a fixed tag per resident (`relay_tag`, `my_relay_tag()`, `private.relay_sender()`), is no longer used and can be dropped in the SQL editor.

## Forced app update (`app.min_build`, 2026-10-19)

`client_config()` returns `min_build`, set on A3 ("Mobile app version"). An app with an older build shows "Update S.A.G.I.P." with the download link `https://sagip.me/download/sagip.apk` (the resident site serves the APK) and keeps only SOS and the hotline, never while the resident's SOS is open or the responder's unit has a job. Apps before build 2 have no such check.

This is the hard stop. The soft notice is not in the database: since build 7 the app reads `https://sagip.me/download/latest.json` (`{"build": N}`, written beside the APK at each deploy, `apps/dashboard/README.md`) and shows "A newer S.A.G.I.P. is out" with Update and Later on every tab when N is higher than its own build, again never during an open SOS or a responder's job.

## Photos on an SOS or a report (migration `incident_photos`, 2026-10-19)

Private bucket `incident-photos` (JPEG, at most 2 MB; the apps shrink to 1280 px and drop EXIF). A resident uploads into `<their account id>/<photo id>.jpg` only, then `attach_photo(photo_id, 'sos' | 'report', record client id)` ties it to their own SOS or crowd report (three at most; not on a closed SOS). Read by dispatchers and admins, the uploader, and the unit assigned to the incident; `incident_photos(incident_id)` returns an SOS's photos and those of the reports in its cluster. When retention anonymizes an incident or report, its photos are hidden (`expired_at`); deleting the files needs the Storage API (Supabase blocks deletes on `storage.objects` from SQL), which is still to do.

## Running the RLS test

With the Supabase CLI and Docker: `supabase start`, then `supabase test db`. The test runs in one transaction that is rolled back, so it is also safe to paste into the hosted SQL editor if it is converted to collect its results (see `docs/PROGRESS.md`, Gotchas).
