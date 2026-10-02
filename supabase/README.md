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
| `functions/send-alerts/` | Works through queued alert deliveries: texts residents of the affected barangays through Semaphore (one SMS each, up to the daily cap), logs every text in `sms_log`, and records each channel's outcome. Also sends rescue confirmations: one text to the resident whose SOS got a unit. `alerts.test.ts` and `index.test.ts` run with `node --test` |
| `functions/sms-intake/` | Receives texts from the gateway SIM, checks the SAGIP1 format and checksum, files the SOS, and returns the reply for the gateway to send; `sms_intake.test.ts` runs with `node --test` |
| `functions/send-sms/` | The Send SMS hook for sign-in codes (Semaphore, or kept in `sms_log` without it); `sms.test.ts` runs with `node --test` |
| `tests/rls_test.sql` | 277 pgTAP checks of who can see and do what |
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
- **Not done:** the data retention period (which records are removed and when is a decision for the team and MDRRMD), EFCOS levels, push (needs the Firebase project), and Facebook posting (needs the page token). `send-alerts` marks those two channels "not set up" for now.

## Sending alerts by SMS (for Joshua, when the Semaphore account exists)

`send-alerts` texts each queued alert to the registered residents of its barangays (everyone for an all-Manila alert): one SMS per resident, cut to 160 characters, never more than the daily cap an admin sets on the Configuration page ("SMS alert limit", 500 by default). Each text is logged in `sms_log`; the delivery row on the Weather page gets the counts, and says so when the cap left some unsent. Simulated alerts are never sent.

1. **Deploy:** `supabase functions deploy send-alerts --no-verify-jwt --project-ref imssgenjfirpohkwxwbv`.
2. **Secrets** (Edge Functions > Secrets): `ALERTS_SECRET` (make up a long random string), `SEMAPHORE_API_KEY`, and `SEMAPHORE_SENDER_NAME` once Semaphore approves it. Without the Semaphore key the function marks SMS deliveries "not set up" and sends nothing.
3. **Call it when an alert is queued:** Database > Webhooks > Create: table `alert_delivery`, event Insert, type HTTP request, POST to `https://imssgenjfirpohkwxwbv.supabase.co/functions/v1/send-alerts` with the header `x-sagip-key: <ALERTS_SECRET>`. Each alert inserts four rows, so the function is called four times; a call with nothing queued does nothing.
4. **Try it:** with simulation mode off, insert a reading that crosses a threshold (see the SQL above), or wait for the PAGASA feed. Check the Weather page's alert log and `sms_log`.

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
- **Sending (for Joshua, with the alert sender).** `send-alerts` sends them, before any alert. After the steps in "Sending alerts by SMS": deploy `send-alerts` again, and add a second Database Webhook: table `rescue_confirmation`, event Insert, the same URL and `x-sagip-key` header. Until then the rows stay `queued` and expire.
- **Before texting for real:** the demo residents' numbers are made up and may belong to someone. Keep simulation mode on while the demo data is loaded, or reload real residents first.
- **Not done:** push (needs the Firebase project). **To confirm with MDRRMD:** which steps are texted, and the wording (English for now): "S.A.G.I.P.: Rescue team R-03 has been sent to your location. Stay where you are if it is safe and keep your phone on. Ref INC-0152."

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

## Loading all 897 barangays

`barangay` holds 10 sample rows. When the Data role delivers the full list (name, district, and ideally boundaries), load it in the Table Editor (import CSV) or a new migration. With boundaries (`boundary`, multipolygon), the Manila check for crowd reports switches from the rough box to the real boundaries automatically.

## Running the RLS test

With the Supabase CLI and Docker: `supabase start`, then `supabase test db`. The test runs in one transaction that is rolled back, so it is also safe to paste into the hosted SQL editor if it is converted to collect its results (see `docs/PROGRESS.md`, Gotchas).
