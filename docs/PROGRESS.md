# S.A.G.I.P. progress and handoff

**Every Claude session reads this file first and updates it before it ends.** It records what is done, what is not, and which areas a session is working on right now, so parallel sessions don't overwrite each other's work and Joshua can trace everything.

Related files: `CLAUDE.md` (rules), `docs/SAGIP-IMPLEMENTATION-PLAN.md` (the full plan), `docs/CONVENTIONS.md` (code patterns).

---

## Session protocol

1. **Read** this file, `CLAUDE.md`, and `docs/CONVENTIONS.md` before touching anything.
2. **Check "Active work"** below. If another session has claimed an area, do not edit its files. Pick something else, or ask Joshua.
3. **Claim** your area before editing: add a row to "Active work" with today's date, what you're doing, and the folders or files you will touch.
4. **Work** in small steps. Run `flutter analyze` and `flutter test` in every package you touched.
5. **Before you stop**, even mid-task:
   - add a dated entry to the "Session log" (what you did, what's verified, what's left),
   - tick or add items in "Status",
   - remove your row from "Active work" (or mark it "paused" with the exact next step),
   - list anything you learned about the tools in "Gotchas".
6. Never rewrite another session's log entry. Add a new one below it.
7. Do not commit unless Joshua asks, and ask before every push. Commits have no Co-Authored-By trailer and use the author `Joshua F. Habana <83832534+angrypoteto@users.noreply.github.com>` (already set in this repo's git config).

---

## Active work

| Started | Session / who | Doing | Files or folders claimed | State |
|---|---|---|---|---|
| 2026-10-01 | f47c816b (Claude, overnight) | Advisories on D10 done; next the incident type classifier (FR12) | `packages/shared` (algorithms, models, mock), `apps/dashboard` (drawer, ARB), `ml/`, `supabase/` (new migration, RLS test, README) | In progress |

---

## Status (what exists and what doesn't)

Legend: `[x]` done and tested, `[~]` partly done or placeholder, `[ ]` not started. Screen IDs match plan section 7.2.

### Planning and design
- [x] Implementation plan: `docs/SAGIP-IMPLEMENTATION-PLAN.md` (Draft 2, one developer)
- [x] Wireframes of the five flows (18 screens): https://claude.ai/artifact/RCjcSsQNdQW42KSS9T48Wr (private until shared from its Share menu)
- [x] Design skill moved to `.claude/skills/sagip-flutter-design/SKILL.md`
- [x] `docs/CONVENTIONS.md`

### Workspace
- [x] Git repo on branch `main`, pushed to the **public** GitHub repo https://github.com/angrypoteto/project-sagip (created 2026-09-30). Commits use angrypoteto's noreply email so GitHub credits that account.
- [x] Root `.gitignore` (build output, `.env`, thesis .docx kept out)
- [x] Pub workspace: root `pubspec.yaml` with `apps/dashboard` and `packages/shared`
- [x] `apps/mobile` created 2026-09-30 (Android, minimum Android 10; a web target exists only for quick previews)
- [x] Android emulator `sagip_pixel` (Pixel 6, Android 15) created on Joshua's machine
- [x] `ml/road_graph/`: builds the Manila road graph from OpenStreetMap (osmnx) and the networkx reference answers for its test (`ml/README.md`)
- [~] CI (`.github/workflows/ci.yml`): formatting, generated translations up to date, analyze and test in all three packages, the Edge Function tests, and a scan for committed keys. Checked locally step by step; **not yet run on GitHub** (it runs on the next push)

### packages/shared (`sagip_shared`)
- [x] Design tokens: `SagipColors` (with text-safe variants), `SagipSpace`, `SagipRadius`, `SagipMotion`
- [x] `SagipPalette` theme extension (tones for light and dark) and `SagipTheme.light/dark(SagipDensity)`
- [x] Plus Jakarta Sans bundled (`assets/fonts`, OFL license included); icons from `material_symbols_icons` (bundled, works offline)
- [x] Automated WCAG contrast audit: `test/contrast_test.dart`
- [x] Models: `Incident` (+ `IncidentEvent`), `CrowdReport`, `ResponseUnit`, `AppUser`, `Resident`, `VulnerableMember`, `UnitSuggestion`, `WeatherStatus`, `AuditEntry`, `GeoPoint` (haversine), all enums
- [x] Repository interfaces: auth, incidents, units, crowd reports, residents, weather, audit, connection
- [x] Algorithms: `dbscan()` (haversine, eps 50 m, minPts 3), `PriorityRules` (provisional weights, read from A3 settings with `PriorityRules.fromSettings`; `checkSetting` mirrors the database's checks), `StraightLineSuggester` (fallback when a unit cannot be routed)
- [x] `MockBackend` + `Mock*Repository`: Manila seed data, role checks, audit log on every action, live simulation
- [x] Shared widgets: `SagipChip` (tint, outline, dashed), status visuals, `EmptyState`, `ErrorState`, `SkeletonBox`, `SkeletonList`
- [x] `SosButton` (2 s hold, progress ring, haptic ticks, early release cancels, tier states, opens the active SOS instead of sending a second), `ConnectivityBanner`, `DeliveryBadge` with `deliveryVisual()`
- [x] Mobile models and interfaces: `SosRequest`, `SosDetails`, `QueuedRecord`, `DeliveryState`, `SignalState`, `LocationFix`/`LocationStatus`, `newClientId()`; `SosRepository`, `OfflineQueue`, `SignalMonitor`, `LocationService`
- [x] `MockMobileBackend` + adapters: saves an SOS on the phone first, sends in capture order over internet, SMS, or nearby phones, keeps the capture time, confirms delivery, then plays the dispatcher (verify, assign R-03, en route, on scene, resolved); updates wait for internet like Realtime
- [x] Shared formatters (`formatTime`, `formatWait`, `formatCoordinates`, ...) and `LiveValue` moved here from the dashboard so both apps use them
- [x] `UnitStatusControl` (56 dp, tinted selected segment that passes WCAG AA) and `EtaHero`; `SagipTiles` and `MapCredit` are the shared map base
- [x] Responder models and interface: `Assignment`, `CompletionReport`, `ResponderState`, `RescueOutcome`, `StatusRejected`, `ResponderRepository`; the mock responder (`mock_responder.dart`) offers assignments, drives R-03, and queues status updates and reports
- [x] Account models and interfaces: `Barangay`, `AppPermission`, `PermissionState`, `PhoneAuthFailure`, `normalizePhMobile()`; `ResidentAccountRepository` (send code, verify, register, request data deletion) and `PermissionService`; the mock (`mock_accounts.dart`) checks numbers, limits code requests to 3 a minute, accepts code `123456`, and records deletion requests; `sampleManilaBarangays` (10 real barangays until the Data role supplies all 897)
- [x] Part 4b models and interfaces: `PublicAlert`, `AlertFeed`, `BarangayForecast` (`alerts.dart`), `CompletedAssignment`, `ReportStage` and `incidentId` on `HazardReport`, `VulnerableMember.id`, `LocationFix.manual`, `Barangay.center`, `nearestBarangay()`, `formatDate()`; `AlertRepository`, `VulnerabilityRepository`, `ResponderRepository.watchHistory()`
- [x] Mock: sample alerts and forecasts (`mock_alerts.dart`), consent and household changes, account-owned SOS and report lists, delivered reports move to "Checking", responder history that follows each report's delivery, and an opt-in history seed (`withHistory: true`, used by `main.dart`; `mock_history.dart`)
- [x] Supabase side of the mobile app (`supabase/mobile_repositories.dart`): `SupabaseMobileBackend` with `SupabaseMobileAccounts` (resident sign-in by code, registration, linking, responder sign-in; implements `AuthRepository` and `ResidentAccountRepository`), `SupabaseVulnerabilityRepository`, `SupabaseAlertRepository`, and `SupabaseMobileRemote` (the server calls the offline queue will send: SOS and details, reports, accept, arrive, on-scene check, status, completion report, position; plus live `my_sos`, `my_crowd_reports`, `my_assignments`, `my_unit_history`, unit). `databaseRefusal()` maps the database's refusal codes to `ReportRejected`, `StatusRejected`, and `ActionRejected`. `liveQuery` gained `refreshOn`. `BarangayForecast.fromRow`, `PhoneAuthFailure.unavailable`
- [x] Tier 2 codec (`algorithms/sos_sms.dart`): `SAGIP1 SOS <id> <lat>,<lng> <accuracy> <time> <flags> <crc>` with CRC-16/CCITT-FALSE, about 85 characters; the TypeScript twin in `supabase/functions/_shared/sos_sms.ts`; both checked against `test/fixtures/sos_sms_vectors.json`. `SmsSender` and `SmsTier` in the sync engine
- [x] Offline layer (`offline/`, part 6a): `OutboxEntry` and `LocalStore` (memory for tests, Hive in the app); `SyncEngine` (saved first, sent in capture order with a save-order tie-break, delivered only on server confirmation, refusals kept as rejected, network failures stop the run and retry with backoff, each account's records wait for that account, a cut-off send is retried after a restart, delivered records kept a day); `ServerSender`; `MobileServer` (implemented by `SupabaseMobileRemote`); `OutboxSosRepository`, `OutboxHazardReportRepository` (same phone checks as the mock), `OutboxResponderRepository` (queued changes shown at once, jobs cached for offline work, jobs the dispatcher closes flagged), `OutboxOfflineQueue`; saved copies for SOS, reports, unit, jobs, history, alerts (read marks kept offline), weather, and profile; `ResponderLocationSharer` (every 15 s while online, plus a heartbeat when standing still); the signed-in account saved for offline restarts
- [ ] Widget gallery
- [x] Dijkstra over the OSM road graph (plan 10.2): `RoadGraph` (bundled asset `assets/road_graph/manila_drive_v1.bin`: 9,296 intersections, 23,716 one-way segments, 2,251 street names, built 2026-09-30), `dijkstra()` with a binary-heap priority queue, `RoadRouter` (routes with street steps and turns, one-to-many times on the reversed graph, nearest intersection within 1 km), `RoadNetworkSuggester` (ranks Available units by road travel time; falls back to straight line per unit), encoded polylines, `RoadRoute` and `RoutingRun` models, and the timing log (`RoutingLogRepository`: memory, throttled, Supabase)
- [ ] Incident type classifier (plan 10.4), LSTM + KDE (plan 10.5), RAG (plan 10.6)

### supabase/ (hosted project `imssgenjfirpohkwxwbv`, see `supabase/README.md`)
- [x] Schema: staff, residents + vulnerable household members, units, incidents + timeline, crowd reports, dispatches, weather, audit log (5 migrations, applied)
- [x] Row Level Security on every table; clients get read-only grants; full contact numbers are hidden (masked column + audited `reveal_resident_contact`)
- [x] Every write is a checked database function: verify, SMS check, false report, confirm type, assign/reassign, resolve
- [x] Audit log written by a trigger on incident changes, plus the functions (FR11); rows made outside the app are logged as "System"
- [x] DBSCAN clustering of crowd reports in the database (`ST_ClusterDBSCAN`, eps 50 m, minPts 3, 60 min)
- [x] Realtime on incidents, timeline, crowd reports, units, weather, audit log, households
- [x] Demo data and tools (SQL editor only): `reset_demo_data()`, `demo_new_sos()`, `demo_add_crowd_report()`, `demo_advance()`, `create_staff_account(...)`
- [x] RLS test: `supabase/tests/rls_test.sql`, 222 pgTAP checks across anon, dispatcher, admin, responder, residents (linked, by phone, new number), and a signed-in account with no role
- [x] Mobile write paths and reads (part 5, 3 migrations): resident linking and registration, SOS (client UUID stored once, capture time kept, vulnerable household types, on the board at once), SOS details, crowd reports (Manila check, 5 an hour by capture time plus 10 received an hour), consent and household changes, data deletion requests, responder accept, arrive, on-scene check, status control, completion reports (resolve the incident, free the unit), position sharing, alert read state; reads in the app's model shapes; DBSCAN counts from capture time
- [x] New tables with RLS: `barangay` (10 samples), `completion_report`, `public_alert`, `alert_read`, `barangay_forecast`, `data_deletion_request`; view `my_alerts`; household members carry `member_id` in `resident_profile`
- [ ] Load the new sample data on the hosted project: run `select public.reset_demo_data();` (not run by the migration, so edits Joshua made are kept until he chooses)
- [x] SMS log (`sms_log`, full numbers, no client access) and the `send-sms` Edge Function for Supabase's Send SMS hook: checks the signature, sends the sign-in code through Semaphore's OTP route, or keeps it in `sms_log` for an hour when no Semaphore key is set (part 6c). **Not deployed or switched on yet** (Joshua: steps in `supabase/README.md`)
- [x] Routing (migration `routing`): `assign_unit` takes the unit's road route and keeps it on the dispatch record (`route` polyline, `route_plan`); `my_assignments` returns it; `routing_run` logs every Dijkstra run's execution time for Chapter 4 (admins read it, `log_routing_run` writes it, 120 a minute per account at most)
- [x] Configuration (migration `configuration`): `app_setting` with the eight priority weights (dispatchers and admins read; realtime), `set_setting` (admins only, range and order checks, audited as `settingChanged`), and `incident_board` returning `priority_score`, `priority_severity`, and `priority_factors` from `private.priority_breakdown` (the same rules as `PriorityRules`)
- [x] Analytics (migration `analytics`): `analytics_report(from, to)`, admins only; times from the incident timeline (dispatch = received to first assignment, verification = received to verified, response = received to on scene, travel = assigned to on scene); days in Manila time; Dijkstra timings from `routing_run`
- [x] Resources (migration `resources`): `response_unit.retired_at`; `save_unit` (add or edit; call sign tidied and unique, crew 1 to 50), `retire_unit` (free units only; takes responders off), `restore_unit`, `set_responder_unit` (responders only, not onto a retired unit); all admin-only and audited (`unitAdded`, `unitEdited`, `unitRetired`, `unitRestored`, `rosterChanged`); `assign_unit` refuses retired units
- [x] Tier 2 SMS (migrations `sms_intake`, `sms_gateway_provider`): `intake_sms_sos` (service role only) files an SOS texted to the gateway by the sender's number (unknown numbers still reach the board, not account-verified, with the nearest barangay), recognises repeats by the SOS id; `submit_sos` attaches the resident when the app's copy of an SOS texted from another SIM arrives; inbound texts logged in `sms_log`
- [~] `sms-intake` Edge Function: written and tested with Node (the shared vectors, both gateway payload shapes, the shared secret, replies under 160 characters); **not deployed** and no gateway SIM yet (steps in `supabase/README.md`)
- [x] Accounts (migration `accounts`): `admin_create_staff` (a random 12-character temporary password returned once), `admin_update_staff`, `admin_set_staff_active` (bans the login, ends sessions), `admin_reset_password`, `admin_set_resident_suspended`; every role check (`current_staff_role`, `_require_dispatcher`, `require_responder`, `require_admin`, `set_setting`, `analytics_report`) now ignores deactivated accounts; a suspended resident's crowd reports are refused and their SOS arrives unverified (triggers); `resident_profile` shows `suspended_at`
- [x] Web form (migration `web_form`): `submit_crowd_report` takes the channel (`app` or `webForm`); the hourly report limit is the setting `reports.per_hour` (5 by default, 1 to 30, set on A3), counted across the app and the web form, with a hard cap of twice the limit received per hour; `my_report_quota()` (limit, used, remaining, when the next report frees up, suspended); `my_crowd_reports()` returns each report's channel
- [x] Threshold engine and the rest of A3 (migration `alert_engine`): settings for alert thresholds (rainfall, wind signal, storm surge; warning and critical), channel switches (push, SMS, Facebook), the hotline and the SMS gateway number, and simulation mode; `set_setting` checks each kind (numbers in range with warning at or below critical, switches, the gateway as a Philippine mobile number kept as +63..., the hotline as digits); `client_config()` gives the two numbers without sign-in; a trigger on `weather_alert` issues a `public_alert` when a reading's level changes and expires the earlier one; `alert_delivery` logs each channel (sent in the apps, queued, off, simulated); `simulate_weather` (admins, simulation mode only, audited as `weatherSimulated`)
- [x] Advisories from the dashboard (migration `advisories`): `issue_alert()` for dispatchers and admins (source MDRRMD, PAGASA, PHIVOLCS, or EFCOS; level; title up to 120 characters; message up to 1,000; up to 8 steps of 200; barangays that exist, or none for all of Manila; simulated while simulation mode is on) and `end_alert()`; both audited (`alertIssued`, `alertEnded`)
- [x] The alert sender's database side (migration `alert_sender`, service role only): `claim_alert_deliveries()` (queued rows become `sending`, so two runs never send twice; rows stuck for 10 minutes are taken again), `alert_sms_recipients()` (registered residents of the alert's barangays), `alert_sms_budget()` (the daily cap `channels.sms_daily_cap`, 500 by default, set on A3), `finish_alert_delivery()` (outcome and counts)
- [~] `send-alerts` Edge Function: SMS through Semaphore (one text per resident, 160 characters, up to the daily cap, every text in `sms_log`), push and Facebook marked "not set up", ended alerts skipped; written and tested with Node (helpers, and the real handler with the database and Semaphore stood in). **Not deployed**, and not checked against the real Semaphore API (no account yet); steps in `supabase/README.md`
- [ ] FCM push, Facebook posting, the PAGASA feed, EFCOS levels (Edge Functions)
- [ ] Data retention period (A3): not built; which records are removed and when needs a decision (RA 10173, NDRRMC reporting)
- [ ] Leaked-password protection is off (Supabase dashboard setting: Authentication, then Passwords); turn it on before the pilot

### apps/mobile (`sagip_mobile`), mock data
- [x] S1 splash (red S.A.G.I.P. mark, also the launcher icon) while the session loads; the role picks the shell: resident Home, Report, Alerts, Me; responder Home, History, Me
- [x] S2 welcome and permissions: three steps (location; notifications; SMS and nearby devices), each says why before asking; Allow, Skip, "Allowed", "Not allowed" with Open settings when blocked; shown once per app run for now
- [x] S3 sign in by mobile number: +63 prefix, number checks ("like 917 123 4567"), unknown number, too many tries, offline notice, Call MDRRMD card; links to register and to the MDRRMD personnel sign-in (email and password); demo account buttons only on sample data
- [x] S4 register: full name, number, barangay picker with search, terms and privacy notice (draft), each missing field explained
- [x] S5 code: 6 digits checked as soon as they are in, wrong-code message, resend after 60 s, change number; the demo code shows only on sample data
- [x] Offline banner on every screen (SMS only, no signal, waiting count, sending, "Back online" for 4 s); tapping opens S6
- [x] R1 Home and SOS: greeting and barangay, PAGASA strip, SOS button with caption below it, GPS-off warning with Open settings, active SOS card, Report a hazard link
- [x] R2 SOS status: state heading and elapsed time, ETA card (unit, minutes), 9-step timeline, Add details sheet (type, people, extra help, note), location card, guidance, Call MDRRMD
- [x] S6 offline queue sheet: records with capture time and delivery badge, what happens next for the current signal, Try sending now, remove a rejected record
- [x] Delivery notice: "Your SOS from 3:42 PM was delivered." (in-app message; a system notification comes with FCM)
- [x] S7 Me: name, role, barangay, number; My activity and Vulnerability profile links; theme (System, Light, Dark); language (English, Filipino later); test notification; privacy notice; request deletion of my data (asks first); sign out warns when records still wait to send; demo tools
- [x] R3 Track responder: full-screen map (shared `SagipTiles`), resident pin, responder marker gliding between updates, dashed line, one card with unit, status, ETA, "Updated 30 s ago" (stale after 2 min), offline "last known position", Call MDRRMD; opened from R2 once a unit is assigned
- [x] R4 Report a hazard: description, optional type, current location, on-phone checks (empty, no location, outside Manila, 5 per hour), saved on the phone and sent over internet only, confirmation with delivery badge, Send another
- [x] Android Back on another tab returns to Home instead of closing the app; tapping outside a text box closes the keyboard
- [x] F1 Responder home: unit, status control with refusals explained, location sharing line, offer card, current assignment with hero ETA, weather strip
- [x] F2 Incoming assignment: full-screen alert (system alert sound and vibration, three pulses), type, place, distance and ETA, vulnerable types, Accept and start, View details; clears leftover messages so nothing covers Accept
- [x] F3 Assignment detail: map preview, offline-map progress (simulated), where to go, what was reported, vulnerable types only (Q9), actions for each stage, Call dispatcher, reassigned banner
- [x] F4 Navigation: map follows the unit, heading arrow, destination pin, recenter, card with compass direction, distance, ETA, "Waiting for GPS", "Offline. Using saved map.", and "You're at the scene" plus Arrived within 50 m
- [x] F5 On scene: real-emergency check with a required reason for No (FR8), people found
- [x] F6 Completion report: outcome, persons assisted, damage counts, notes, time on scene, draft kept while moving around the app, saved offline and sent later
- [x] R5 Location picker ("Change" on R4): map under a fixed pin, GPS dot and accuracy ring, Use my GPS, barangay search, "Near Barangay 412, Sampaloc" from the nearest sample barangay; offline: the GPS fix or a barangay from the list. R4 shows "Chosen by you" and "Use my GPS instead"
- [x] R6 My activity: SOS and Reports tabs, rows with type, capture time, and a status chip or delivery badge; an SOS opens R2; a report opens a sheet with its steps (Received, Checking with nearby reports, Part of a confirmed incident, Resolved) and what it means
- [x] R7 Alerts and forecast: alert cards (level chip, source, affected barangays, time, unread dot), unread count on the Alerts tab, pull to refresh, "Offline. Last updated 3:42 PM."; Forecast tab: 72-hour flood, fire, and storm surge risk for the resident's barangay, valid-until time, sample-data note, preparation tips for the riskiest hazard
- [x] R8 Alert detail: level, title, issue time, text, affected areas, what to do; opening it marks it read
- [x] R9 Vulnerability profile: consent status, household cards with type chips and notes, edit and remove (asks first), withdraw consent (deletes the list), add button; offline: read-only with a note
- [x] R10 Data privacy consent: what is kept, why, who sees it, how long, how to withdraw (RA 10173); I agree only after the checkbox and online
- [x] R11 Household member: name or description, type chips (at least one), notes, a line that the home address is used; offline: Save disabled
- [x] F7 Assignment history: rows with incident, type, barangay, time, outcome, and "Saved on phone" until the report reaches the server; All, This week, Last week
- [x] Road routes on the phone: Dijkstra runs on the phone from every new position (works offline and re-routes); F3 and F4 draw the road route, F4 shows the next turn ("Turn right onto España Boulevard, in 300 m") and the road ETA; F1 and F2 use road ETAs; straight line only when the graph cannot route
- [ ] Real offline map tiles (F2/F3 progress is simulated), spoken turn-by-turn, a custom alert sound (FCM work)
- [ ] Real barangay boundaries for the Manila check and the picker's "Near ..." line (needs the Data role's boundary file)
- [~] Real texted codes: the Send SMS hook is written (part 6c); resident sign-in on Supabase works once Joshua deploys it and switches Phone sign-in on (`supabase/README.md`)
- [ ] Cancel SOS (waits on plan Q10), nearest evacuation center card on R7 (waits on Q38 data), a separate pin for a household member who lives elsewhere (needs a schema change, plan Q14), the MDRRMD hotline number itself (an admin enters it on A3 once MDRRMD provides it; until then Call MDRRMD says it is not set)
- [x] The real app (part 6b): with `apps/mobile/.env` it runs on Supabase (`liveOverrides`), with an encrypted Hive store (AES key in Android secure storage), GPS through `geolocator` (keeps the last fix, flags mock locations), a signal monitor that checks the server answers (not just Wi-Fi), and real Android permission prompts on S2. Without `.env` it runs on sample data as before
- [x] Welcome-seen and theme saved on the phone
- [x] Screens never promise what the real app cannot do yet (`DeviceCapabilities`): offline banner and queue sheet say records are saved and sent when back online; the offline-map row on F3 is hidden
- [x] The hotline and the SMS gateway number come from A3 (`client_config()`), fetched when the app starts and kept on the phone for offline; `MDRRMD_HOTLINE` and `SMS_GATEWAY_NUMBER` at build time still work and take priority. Tier 2 is offered only once a gateway number is known
- [x] Tier 2 on the phone: with signal but no data an SOS is texted once to the gateway (`SMS_GATEWAY_NUMBER` in `.env`) in the SAGIP1 format, shows "Sent by SMS", and still goes over the internet later (the server recognises it); failed texts retry; screens say SMS is available only when the gateway number is set. `MainActivity.kt` sends through `SmsManager` (checked on the emulator with an integration test)
- [ ] BLE tier 3 on the phone, real offline map tiles (Phase 5); a fallback that opens the SMS app when the permission is refused

### apps/dashboard (`sagip_dashboard`), runs on Supabase (with `.env`) or mock data
- [x] D1 Staff sign in (demo accounts shown only in mock mode)
- [x] Shell: top bar (PAGASA summary, live/offline indicator, clock, user menu with theme toggle and demo connection switcher), navigation rail (admin items hidden for dispatchers), offline/reconnecting banner, new-SOS toast
- [x] D2 Command Board map view (incidents, units, unverified reports, layers, legend, zoom)
- [x] D3 list view (table)
- [x] D4 Incident drawer: status, rank, wait timer, type confirm/override, verification (call resident, SMS check, mark verified, mark false report), resident and vulnerable household, cluster reports, priority breakdown, suggested units, assigned unit, reassign, mark resolved, timeline
- [x] D5 Override dialog (reason required) and "Choose another unit" dialog
- [x] Suggested units ranked by road travel time (Dijkstra, one run per incident on the reversed graph); Assign sends the unit's road route; each run is timed and logged
- [x] D6 Crowd reports: confirmed clusters with 50 m ring, unverified singles
- [x] D7 Units table with status counts and stale-GPS flag
- [~] D8 Forecast: placeholder page (waits on LSTM + KDE)
- [x] D9 Vulnerable Resident Priority List (numbers masked; revealing is audited)
- [x] D10 Weather and advisories (PAGASA simulated; EFCOS and PHIVOLCS marked not connected); each reading shows Warning or Critical against the A3 thresholds, storm surge as a height, and "Alerts sent": every alert with its level, source, area, Simulated and Ended marks, and each channel's outcome. "Issue an advisory" (FR6, FR14): who it is from, level, title, message, what to do, all of Manila or chosen barangays, then a review step that shows it as residents will see it and where it goes (or that simulation mode sends nothing). "End alert" on each alert still showing, asked first. Both are off while offline
- [x] D11 My account: account details, theme (dark, light, or the computer's), password change (checks the current password, at least 8 characters, the two new ones match), keyboard shortcuts; "My account" in the user menu
- [x] A3 Configuration, the rest: alert thresholds (six numbers, each warning at or below its critical value), alert channels (three switches that apply at once), numbers shown in the apps (hotline and SMS gateway, checked and normalised), simulation mode (switch, then Typhoon, Heavy rain, or Calm readings), and a question before leaving the page with unsaved changes. Not built: the data retention period (needs a decision) and EFCOS thresholds (no feed)
- [~] A3 Configuration: the Triage Queue priority weights (range checks, High at or below Critical, discard, a live preview of the ranking with the draft values, last changed by) and the thesis's algorithm parameters read-only; saved on Supabase and audited. The crowd report limit is done (below). Not yet: alert thresholds, SMS gateway number, channel switches, data retention, simulation mode, a guard against leaving with unsaved changes
- [x] A4 Analytics: last 24 hours, 7 days, or 30 days; KPI tiles (incidents, median and average dispatch time, median and average response time, average verification time, SOS by channel, Dijkstra run time); a note that the MDRRMD baseline has not arrived; incidents per day; tables by type, barangay (top 10), and unit (travel time); CSV export (browser download). Browser-checked on mock data
- [x] A2 Resources: unit table (call sign, type, station, crew, status or Retired, responders) with add and edit (field checks first), retire (asks first; only a free unit; its responders come off it), and restore; the responder roster with a unit picker per responder. Changes are audited
- [x] A1 Accounts: Staff, Responders, and Residents; create an account (email, name, role, unit for responders) and show the temporary password once with Copy; edit name and role; reset password; deactivate and reactivate (asks first); no actions on your own row; suspend a resident and lift it (asks first)
- [~] A5/A6 NDRRMC reports: placeholder pages (Tier 3)
- [x] A7 Audit log
- [x] G1 Not found (also used to hide admin pages from dispatchers)
- [x] G2 Session expired: when a session ends without signing out (Supabase refresh failure; a demo menu item on mock data), the dashboard says so and returns to the same page after signing in
- [x] W1 to W3 resident web form: a second entry point (`lib/main_webform.dart`, `lib/src/webform/`), phone-sized and following the device's light or dark setting. W1: mobile number and code (bad number, no account, wrong code, too many tries, offline explained), creating an account with name, barangay, terms, and the privacy notice (on by default; plan Q13), the "SOS is only in the app" notice with the hotline and app link when set. W2: description, optional type, location from the browser, a pin on the map, or a barangay (nothing is sent until one is chosen), reports left this hour, outside Manila and the limit explained, a suspended account told so, the draft kept in the browser through a reload or a lost connection and sent again with the same id. W3: the reference, the reminder that one report is never confirmed on its own, and the account's recent reports with their stage and channel
- [x] A3: the hourly crowd report limit (its own card, range check, audited)
- [ ] New-SOS sound (toast exists, no sound yet)
- [ ] Enter key on the queue (arrow keys and Esc work)
- [ ] List view: at 1440 px the table scrolls sideways; consider hiding low-value columns when the drawer is open
- [ ] Crowd reports map: the 50 m ring is only a few pixels at city zoom; add a count marker for clusters

### Tests (last run 2026-09-30)
- `packages/shared`: 184 passing (`flutter test`), including advisories (the rules matching `issue_alert`, a relayed advisory stored tidied and queued per channel, refusals, ending once with what was waiting not sent, simulation mode, the audit entries) and the alert engine (levels at each threshold, thresholds from the A3 settings, the same reading sequence as the RLS test, the alert text matching the database, setting checks for numbers, pairs, switches, the gateway number and the hotline, the mock raising simulated alerts that expire and are replaced, simulation mode and admin required, audit entries, rows with switches and text, a `public_alert` row with its deliveries, `client_config`, readings with and without a surge height), the gateway number arriving later and the saved copy of the two numbers for offline, the web form (a report delivered at once and marked as from the web form, the same report stored once, outside Manila, empty, and offline refused, the hourly limit counted across the app and the web form and freed after an hour, a suspended account, signed out; `my_report_quota` and the channel in `my_crowd_reports` rows; the limit as an A3 setting with its range, the audit entry, dispatchers refused), A1 (create, duplicate and bad email refused, own account refused, deactivated accounts cannot sign in, reactivation, password reset, dispatchers refused, resident suspension, rows with `deactivated_at` and `suspended_at`, the new refusal codes), tier 2 (the codec against the shared vectors, the CRC check value, refusals with reasons; the sync engine texts an SOS once with signal but no data while reports wait, shows it as sent by SMS, sends it over the internet later with no second text, keeps "sent by SMS" after a failed internet send and after a restart, retries a failed text, texts nothing with no signal), A2 (the mock follows `save_unit`, `retire_unit`, `restore_unit`, and `set_responder_unit`: tidy call sign, duplicate and zero crew refused, the edit spelled out in the audit log, a busy unit kept, the crew taken off a retired unit, retired units off the board and never assigned, dispatchers refused; rows with `retired_at` and staff rows parse), analytics (the same figures as `analytics_report` on the demo timeline, the period filter, Postgres-style percentiles, Manila days, a live report row, CSV, admins only), A3 settings (rules from the default settings, the same scores as the database on the demo incidents, the range and order checks, the mock refusing dispatchers and auditing admins, real `app_setting` rows), Dijkstra (27: the binary heap, one-way streets on a small block, the reversed graph, early stop, the Manila graph decodes, **matches networkx on 50 random origin and destination pairs** and on a one-to-many run, every intersection reaches every other, nearest intersection agrees with a full scan, routes from start to end with steps, one-way differences, JSON, off-map points, one-to-many equals point-to-point, suggestions by road with busy units skipped, per-unit and whole-graph fallback, the timing log and its throttle, route helpers, an assignment keeping its route through the phone cache, a bad server route dropped, the mock keeping the route, polylines, turns; 50 point-to-point runs took 59 ms in total on the dev PC), the offline layer (capture order, notices only after waiting, network failure and retry, refusals kept, other accounts wait, restart recovery, JSON round trip, SOS shown at once offline then as the server has it, report checks and the hourly limit, merging, a responder job worked offline end to end, a closed job, saved copies, alert read marks offline, position sharing with heartbeat), the server rows above, part 4b (alerts newest first and unread count, forecast by barangay and none for some, refresh offline keeps the saved time, add, edit, remove, withdraw and consent, changes need internet, history seed visible to Maria only, delivered reports go to Checking, a map pin is sent without accuracy, responder history with a report waiting, nearest barangay, JSON for the new models), accounts (number formats, unknown number, the 3-a-minute code limit, register then verify, deletion request, permission states), Supabase-shaped JSON, the mobile mock's offline rules (capture order, capture time kept, SMS and relay tiers, updates held while offline), and the SOS button (a tap never sends, a 2 s hold sends once, early release cancels, the release after a send does not also open), hazard reports (wait for internet while an SOS goes by SMS, delivered in capture order, the four on-phone checks), the responder closing in with a falling ETA, and the mock responder (offer and accept, refused status moves, completion makes the unit available, offline updates and the report sent in capture order)
- `apps/mobile`: 21 passing (the hotline from A3 or "not set yet"; the responder flow now checks F4 shows the road route note and a turn instruction; an offline SOS through the real outbox behind the real screens: honest offline banner, waiting count, delivered on reconnect with the notice; saved theme and welcome; R6 history and the report sheet; R6 empty for a new account; R7 unread count, reading two alerts, forecast, offline line; R9 to R11 validation, add, remove, withdraw, consent again, offline; R5 by search and by barangay offline, sent without accuracy; F7 week filters and a report saved on the phone; first run: welcome steps then sign-in by code, wrong code; bad and unknown numbers and the offline notice; register with the barangay picker; Me: theme, deletion request, sign-out warning; the role picks the shell, and Back on another tab goes Home; online SOS to responder assigned; offline SOS by SMS, queue sheet, delivered on reconnect; add details; tracking before and after assignment; reporting: empty check, online, offline; responder offer, accept, navigate, arrive, on scene, report; responder offline report and the required reason)
- Live check on the emulator against the hosted project (2026-09-30, part 6b): real Android prompts on S2 (location, notifications, SMS, nearby devices); resident sign-in shows "Couldn't send or check the code right now" (the SMS hook is not on yet) and sends nothing; a temporary responder account for R-12 signed in; a test incident assigned by SQL reached the phone over Realtime within seconds and opened F2; Accept reached the server (incident and unit En route, timeline and audit log under the responder's name); with the network off, Mark on scene, the on-scene check, and the completion report waited on the phone ("3 waiting to send", unit shown Available); on reconnect all three reached the server in order with their offline capture times (report made 22:54:15, received 22:54:50); History showed the job; restarting the app offline kept the account and the saved unit and weather. Found and fixed: the sign-in error was cut to one line (inputs now wrap errors to three lines); position sharing only sent on movement, so a parked unit went stale (heartbeat added). Cleaned up afterwards: test incident, its timeline, dispatch, report, audit rows, and the account deleted; R-12's position restored.
- Emulator check, part 4b (2026-09-30): Alerts with the unread count (3, then 2 after reading), alert detail, forecast, My activity (SOS and Reports), the report sheet, Vulnerability profile, the add-member checks, R5 with real map tiles (pin stays centred, coordinates and "Near" update while dragging), and F7 in light and dark. Found and fixed: the alert card header overflowed at phone width with long dates (time moved under the title); the unread dot moved sideways between cards; report and history titles were cut at half the row because the chip took half; "Withdraw consent" was inset from the text; the R5 pin tip sat about 4 dp above the chosen point. Checked by widget tests only: R5 offline, R10, the offline states. Not checked: dark theme on every new screen (History was checked).
- Emulator check, part 4a (2026-09-30): launcher icon, S2 steps with Allow, S3, S5 with the demo code landing on Home ("Hi, Maria"), S4, and Me all render. Found and fixed: the main S2 button jumped down when Skip disappeared after Allow; the hotline call icon was grey on blue (the app theme greys every icon button, even filled ones); the register barangay row read "Choose your barangay / Barangay" (label and hint swapped). Not checked on the emulator: the staff form, dark theme on every new screen.
- Emulator check, part 3 (2026-09-30): the full responder job on Android: F1, the F2 alert, accept, F3 with the map progress reaching "saved", F4 following the unit to the scene, Arrived, F5, F6, back to Available. Found and fixed: the F2 background was a translucent tint over the black window (unreadable); status segments did not fill their height; a leftover message covered Accept; arrival showed "Head north · 0 m" and "1 min"; location sharing went stale after the drive. The arrival card fix is checked by the widget test, not re-run on the emulator.
- Emulator check, part 2 (2026-09-30): R3 map with real OSM tiles, gliding marker, falling ETA, arrived state; R4 typed, sent, and delivered; Back from R3 to R2 to Home. Found and fixed: Back on the Report tab closed the app; "Track responder" competed with Call MDRRMD; the unit line wrapped; a repeated "arrived" message; the delivery notice covered the next form's Send button.
- Dashboard after the map base moved to shared: tests pass and a browser screenshot of the board looks the same.
- Emulator check (2026-09-30, `sagip_pixel`, driven with adb): sign-in, Home, a real 2.6 s hold with the progress ring, R2 timeline updating live to Verified, offline banner, offline SOS showing Sent by SMS, and the queue sheet all work. Found and fixed: the release after a completed hold opened R2 twice; a redundant badge on R2; the active SOS card's link crowded long states. Haptics not checked (the emulator does not vibrate); needs a real phone.
- `apps/dashboard`: 28 passing. Dashboard (`dashboard_test.dart`, 19) now also covers advisories on D10 (the checks before the review, the review text, issuing, ending with a confirmation, both audited, the button off while offline, the simulation notice and Back keeping the text), the rest of A3 (a warning above its critical value explained on both fields, a threshold saved, a channel switched off, the gateway refused then normalised, simulation mode gating the buttons, a simulated typhoon), D10 (levels against the thresholds, the three alerts raised, the delivery lines, the audit entries), and the unsaved-changes question (Stay keeps the edit, Leave drops it, nothing asked when clean). Web form (`webform_test.dart`, 9, with the hotline from A3): W1 number checks, a wrong code, the code opening W2, the notice with the hotline; creating an account with each missing field explained; registration switched off; W2 empty description, no location, the browser refusing its location, the browser location, send, W3 with the reference and the list, the next form empty with one report fewer; a barangay, the map pin, outside Manila refused before sending; offline (banner, Send off), the draft back after a reload, a lost connection during Send, then sent once; the hourly limit and a suspended account; no reports yet, and sign-out clearing the draft. Dashboard (`dashboard_test.dart`, 14): the A3 report limit (range check, save, audit entry); A1: create with the temporary password shown, no actions on your own row, deactivate after confirming, suspend a resident, audit entries; D11: theme, the password checks and a successful change, signing in with the new password; G2: expiry shows the page and signing in returns to Units; A2: field checks, a duplicate call sign explained, add, roster change, a busy unit's Retire off, retire after confirming, the crew taken off, audit entries; A4: figures for the period, switching periods, CSV export; A3: out-of-range and High-above-Critical explained with Save off, a saved weight reaching the queue rules, last changed by, the audit entry; sign-in, ranked queue, assign top unit with suggestions by road and the route sent with the assignment, override needs a reason, admin pages hidden, admin audit log, offline disables actions)
- Browser check of the road ranking (2026-09-30, headless Chrome driving the release web build on mock data): the drawer says "Available units, by travel time on the road network" (R-02 3 min 0.9 km, A-05 6 min 2.8 km, R-04 10 min 4.8 km for the Tondo flood cluster), and Assign R-02 worked. So the graph loads and Dijkstra runs under JavaScript. Not checked: the dashboard on Supabase sending a route (covered by the RLS test's dry run and the widget test), the phone's F4 on the emulator
- `supabase/tests/rls_test.sql`: 222 of 222 passing, run in full with the `advisories` migration in a rolled-back transaction on the hosted project (2026-10-02). Advisories added 16 (anon and residents refused; a dispatcher relays a PHIVOLCS advisory, stored tidied; app sent and push and SMS queued; a blank title, an unknown level, and an unknown barangay refused; residents see it, then not after it ends; ending twice; an unknown id; simulated in simulation mode; both actions in the audit log). The 10 for the alert sender ran with its migration in a rolled-back transaction on the hosted project (only the service role may claim, list numbers, or record outcomes; every queued delivery claimed once; a switched-off channel not claimed; one barangay's residents only; an outcome recorded once; the daily cap counting today's texts). The first 196 last ran in full just before (the alert engine and the rest of A3 added 25: who may read the two numbers and the delivery log, the sample alerts never sent outside the apps, simulation needing an admin and the mode, a simulated typhoon raising three critical alerts marked simulated with simulated deliveries, the audit entry, nothing new at the same level, alerts expiring when conditions ease, a warning replaced by a critical, thresholds kept in order, a channel switched off, the gateway and hotline checks, a real reading queuing deliveries on the channels that are on; the web form added 13: anon cannot send or read a quota, a full quota at the start, a web report stored with its channel and not confirmed on its own, the channel in the resident's list, the quota counting it, an unknown channel refused, the same report stored once, an admin setting the limit, the limit never zero, the new limit applied at once, the quota showing none left and when, staff refused; accounts added 17: anon and dispatchers refused, create with a 12-character temporary password, duplicate and malformed emails refused, own account refused, deactivation cuts access at once, reset, rename, reactivate, suspension refuses crowd reports, lifting it, the audit trail, a suspended resident's SOS still arrives unverified; tier 2 added 9: only the service role can file an SMS SOS, a registered sender finds the resident, the SOS is on the board at once with its capture time, a repeat is stored once, an unknown number still reaches the board unverified with the nearest barangay and the mock flag, a short sender refused, the app's copy of an SOS from another SIM accepted and attaches the resident; resources added 15: anon and dispatchers refused, add with a tidied call sign, duplicate and zero crew refused, edit, a busy unit kept, roster, only responders on the roster, retire takes the crew off, a retired unit never dispatched and never crewed, restore, every change audited in order; analytics added 5: anon and dispatchers refused, counts and median dispatch, verification, and response times checked against the demo timeline, the Dijkstra timings included, a backwards period refused; configuration added 13: weights readable by dispatchers only, the board's score and severity on two demo incidents, dispatchers cannot change settings, an admin's change moves the score at once, out-of-range, High above Critical, wrong type, unknown key, the audit entry, anon; routing added 11: a malformed route refused, the route kept on the dispatch record, the responder's job carrying it, the timing log written by dispatchers and responders, refused for residents and anon and for unknown kinds, readable by admins only; part 6c added the SMS log check; part 5 added 58: SOS stored once with capture time and vulnerable types, the mock-location flag hidden from residents, Manila check, hourly limit, report stages, consent and household, linking and registering by phone, another resident's SOS hidden and untouchable, responder accept/arrive/on-scene/report/status/position, alerts and read state, forecasts, audit entries under the responder's name, anon and private-helper privileges), run on the hosted project inside a rolled-back transaction
- Live API check (2026-09-30): a temporary responder account called the new functions through the REST API (the app's path): reads returned JSON, refusals came back as codes (`no_assignment`, `not_allowed`), anon was denied. The account was deleted afterwards and nothing was changed.
- `supabase/functions/send-alerts/`: 14 passing (`node --test`). `alerts.test.ts` (8): each of the six automatic alert texts fits one SMS whole, a long alert is cut at a word and never inside the title, numbers made local and unique, the daily cap, batches of 1,000, counting what Semaphore accepted, the outcome with its counts and notes, the reasons for channels with no provider. `index.test.ts` (6) runs the real handler with Deno, the database, and Semaphore stood in: no secret, no action; an alert texted once per resident and logged; the cap; a refusal by Semaphore; no key; nothing queued
- `supabase/functions/sms-intake/sms_intake.test.ts`: 6 passing (`node --test`): the Dart vectors decode and re-encode identically, refusals, both gateway payload shapes, replies fit one SMS, the shared secret
- Emulator (2026-10-01): `integration_test/sms_channel_test.dart` sent a SAGIP1 text through `MainActivity.kt` (the emulator's Sent folder has it), and the TypeScript decoder read that exact text back
- `supabase/functions/send-sms/sms.test.ts`: 6 passing (`node --test`, Node 24): the code message fits one SMS, number forms for Semaphore, masked numbers for logs, the payload read defensively, a correctly signed hook call accepted, and a changed body, wrong secret, old timestamp, or missing headers refused. The migration was also dry-run in a rolled-back transaction (old development codes deleted, no client can read the table). Not tested: the deployed function end to end (not deployed yet)
- `packages/shared`: `supabase_mobile_json_test.dart` parses rows captured from the hosted functions into the app's models, and checks the refusal mapping
- Browser check on Supabase (2026-09-30, headless Chrome, 1440 x 900): dispatcher sign-in; board loaded from the database; realtime delivered a new SOS toast and a new DBSCAN cluster without reload; "Show number" revealed the full number; "Mark verified" and "Assign" worked; all five actions appear in `audit_log` under R. Santos. Demo data reset afterwards. Not yet checked in the browser: admin sign-in and the audit log page on Supabase, crowd reports, units, and weather pages on Supabase.
- Browser check of the web form (2026-10-02, headless Chrome at phone width, the release build on sample data): W1, the code step, W2 with real map tiles, the barangay dialog moving the map and turning the pin blue, Send, W3 with the reference and the list, the draft gone from local storage; Chrome's geolocation refused (the message appears) and granted with an emulated position ("Near Barangay 412, Sampaloc", "accurate to 18 m"); Chrome set offline ("You're offline.", Send off). Not checked: the web form on Supabase (resident sign-in needs the Send SMS hook, which is not on yet), dragging the map in a real browser (covered by the widget test), light theme
- Browser check of A3 and D10 (2026-10-02, headless Chrome at 1366 x 768, the release build on sample data): the new cards render (thresholds, channels, numbers, simulation), simulation mode turned on, a simulated typhoon sent, and the Weather page showed three Critical readings with their thresholds and the three new alerts with their channel lines. Found and fixed: the alert log rows were centred in the card instead of left-aligned; the demo's rainfall drift changed a simulated reading (it now stops once an admin simulates one). Not checked: A3 and D10 on Supabase in a browser (covered by the RLS test's dry run on the hosted project), light theme
- `flutter analyze`: no issues in both packages
- `flutter build web --release`: builds
- Browser check (2026-09-30, headless Chrome at 1440 x 900 driving the real build): sign-in, board, drawer, new-SOS toast, list view, and crowd reports all render and work; the simulated SOS arrived and the Dapitan St cluster formed live. Screenshots were taken but not saved in the repo.

---

## How to run

```bash
flutter pub get                                        # once, at the repo root
cd apps/dashboard
flutter run -d chrome --dart-define-from-file=.env     # on Supabase (needs apps/dashboard/.env)
flutter run -d chrome                                  # on mock data
flutter test                                           # dashboard tests
cd ../../packages/shared && flutter test
```

In VS Code, the Run and Debug panel has "Dashboard (Supabase)" and "Dashboard (mock data)" (`.vscode/launch.json`).

**On Supabase:** `apps/dashboard/.env` holds the project URL and publishable key (git-ignored; copy `.env.example`). Staff accounts are `dispatcher@sagip.test` (R. Santos) and `admin@sagip.test` (E. Navarro). Their password is not in the repo; Joshua has it. Change data in the Supabase Table Editor, or run `select public.reset_demo_data();` in the SQL editor to start over (more in `supabase/README.md`).

**Mobile app (mock data):**

```bash
flutter emulators --launch sagip_pixel               # start the Android emulator
cd apps/mobile
flutter run                                         # picks the running emulator
flutter test
```

The first screen after the splash is the welcome steps (Allow or Skip each). On sign-in, tap "Continue as resident" or "Continue as rescue personnel", or type 917 000 4821 and the code 123456 to go through the real flow. The app starts with sample history (a past SOS, three reports, five past assignments) and four alerts. Hold SOS for 2 seconds. In Me, the demo tools switch the signal (Internet, SMS only, No signal) and GPS. After an online SOS the simulated dispatcher verifies it after about 8 s, assigns R-03 after 14 s, and so on to Resolved after about 70 s.

**Mobile app on Supabase:** copy `apps/mobile/.env.example` to `.env` (same values as the dashboard's), then `flutter run --dart-define-from-file=.env` in `apps/mobile`, or "Mobile (Supabase)" in VS Code. Responders sign in with a staff account (`create_staff_account(..., 'responder', 'unit-r03')`). Residents need the Send SMS hook switched on first (steps in `supabase/README.md`); until Semaphore is set up, read the code in the `sms_log` table.

**Dashboard on mock data:** same emails, password `sagip-demo`. What the mock demo does by itself after sign-in:
- about 20 s: a new SOS arrives from Barangay 128, Tondo, flagged "Location may be faked" (toast appears on any page)
- about 35 s: a third crowd report on Dapitan St turns into a confirmed flood cluster (DBSCAN)
- assigned units accept after 6 s, drive to the incident, arrive, and resolve 90 s after arriving
- "Send SMS check" gets a simulated YES reply after 6 s
- user menu → "Demo: connection" simulates going offline or reconnecting

---

## Decisions and deviations (keep the thesis in sync)

| What | Why | Thesis impact |
|---|---|---|
| OpenStreetMap instead of Google Maps | Google gives no road graph for our Dijkstra and forbids offline tiles | Update Ch 3 and figures (plan Q1) |
| Dev map tiles come from `tile.openstreetmap.org` with a dark filter | Fast start; allowed for light development use only | Must switch to self-hosted Manila tiles before the pilot (plan risk 8) |
| `material_ui` package instead of `flutter/material.dart` | Flutter 3.47 moved Material out of the SDK | None |
| Text colors adjusted: `signalStrong #B8232E`, `tideStrong #1C5FB5`, `verdantInk #0C6E48`, `signalLight #FF858A`, `tideLight #7DB4F3` | The first values failed WCAG AA on chip tints (found by the contrast test) | Update plan 7.5 values when convenient |
| Priority weights: SOS 50, cluster 40, vulnerable 30, waiting 2/min (max 30), mock location -20; critical ≥ 80, high ≥ 50 | Provisional until the MDRRMD triage SOP arrives | Plan Q15, Q20 |
| Unit ranking by straight-line distance × 1.3 at 20 km/h | Stand-in until Dijkstra; the UI labels it "estimated by straight-line distance" | None once Dijkstra lands |
| Override reason stored as the chosen label text (plus note) | Simple for now | Consider a reason code in the Supabase schema |
| Assigned-but-not-moving units keep status `available` with `currentIncidentId` set | FR9 has only three unit statuses (plan Q11) | Decide Q11 |
| Dashboard wired to Supabase during Phase 1 | Joshua asked for it (2026-09-30) so demo data is easy to change; screens still only use repository interfaces | None |
| One `staff` table for dispatchers, admins, and responders (residents in `manila_resident`) | Simpler RLS than one table per role | Check against Figure 3.6 (plan Q8) |
| Clients never write tables directly; every write is a security-definer function that checks the role and logs the action | One place for rules and the audit log (FR11, NFR4) | Describe in Ch 3 security design |
| Contact numbers reach the dashboard masked; the full number comes from `reveal_resident_contact`, which writes a `contactViewed` audit row | Data Privacy Act (NFR4) | Mention in Ch 3 |
| Enum values stored as checked `text` columns with the exact Dart names (`pendingVerification`, `enRoute`, ...) | Same names end to end, no mapping layer | None |
| Demo tools are SQL functions that the app cannot call | Reset and demo scenarios from the SQL editor; no demo backdoor in the API | None |
| While an SOS is active, the SOS button opens its status instead of sending a second one | Avoids duplicate SOS from repeated holds; the button is never disabled | Mention in Ch 3 SOS design |
| The SOS button's caption sits under the button, not inside it | Small white text on the signal red fails WCAG AA | None |
| When an SOS goes out by SMS after a Bluetooth relay, SMS is recorded as the channel | A relay may never reach anyone; SMS reaches the gateway | None |
| The mobile app has a web target for quick previews only | Faster checks; the product stays Android only | None |
| Responder status updates, the on-scene check, and completion reports go over the internet only | CLAUDE.md escalation tiers are for resident SOS | Confirm with the team |
| F2 has no Decline button | Declining is not in the thesis (plan Q10) | Decide Q10 |
| F2 uses the phone's standard alert sound and vibration | A custom siren comes with push notifications | None |
| The unit cannot go back to Available until the completion report is filed | Keeps FR9 status and the report together | Confirm with MDRRMD |
| Mobile "was delivered" notices only for records that waited in the offline queue | A record sent at once already shows its status on screen; the extra notice covered the next form's Send button | Matches NFR1 wording |
| Hazard reports go over the internet only; SMS carries SOS only | Keeps the SMS gateway for emergencies | Confirm with the team |
| Report limit 5 per account per hour | FR15 and NFR7 give no number | Provisional; plan Q-list |
| The phone's Manila check is a rough box until barangay boundaries are bundled | R4 needs a check now; the server checks again (FR15) | None |
| Mock responder drives in a straight line from its station | Dijkstra routes come in Phase 4 | None |
| Residents sign in with a mobile number and a texted code; responders use the staff email and password form | Matches plan S3 and the plan's Supabase phone sign-in; responders are staff accounts | None |
| Mobile barangay list holds 10 real sample barangays | The full list of 897 comes from the Data role | Replace before UAT |
| The privacy notice text is a draft written from RA 10173 | No approved notice exists yet | Team, MDRRMD, and the data protection officer must review it before UAT |
| "Request deletion of my data" sends a request to MDRRMD instead of deleting at once | Incident records may be needed for NDRRMC reports and the audit log | Describe the retention rule in Ch 3; confirm with MDRRMD |
| Every welcome permission can be skipped | SOS still works (it falls back to SMS, and asks for location again when needed) | None |
| Code requests limited to 3 a minute per number (mock) | Stops texting costs from repeated taps | Set the real limit in Supabase |
| A report's life after delivery is shown as stages: Received, Checking with nearby reports, Part of a confirmed incident, Resolved, or Not confirmed when no one else reported it within the hour | Explains FR7 to the resident without calling a single report confirmed | Mention in Ch 3 crowd reporting |
| Household members use the resident's home address; no separate pin yet | The `vulnerable_member` table has no location column | Plan Q14; add a column if the team wants it |
| Withdrawing consent deletes the household list at once | No profile may be kept without consent (NFR4) | Mention in Ch 3 privacy |
| R5 names the barangay from the nearest sample barangay centre within 400 m, otherwise shows only the pin | No barangay boundaries yet; the server decides the barangay | Replace with a boundary lookup |
| A report placed by hand is sent with no GPS accuracy | The accuracy would mean nothing | None |
| Unread alert count on the tab uses tide, not red | An unread alert is not an emergency on its own (design skill: no red for non-emergency UI) | None |
| Forecast risk chips: low outline, moderate ember, high signal | Matches the dashboard heatmap colours | None |
| Sample alerts, forecasts, and history are mock content; the forecast says "Sample forecast" | LSTM + KDE is not trained yet; the thesis promises a simulated live feed | None |
| The sign-in code is sent to any valid number; "no account yet" shows after the code is checked | A "does this number have an account" lookup would let anyone find out who is registered (RA 10173) | Update the S3 flow text in Ch 3 |
| A number MDRRMD already has (resident record without an app account) is linked on first sign-in | Residents registered by MDRRMD keep their household list | None |
| The responder's completion report resolves the incident (or marks it a false report) and frees the unit | One step for the responder; the dispatcher can still resolve from the dashboard | Confirm with MDRRMD |
| "Real emergency" in the on-scene check counts as verification on scene when no dispatcher verified it | FR8 names on-scene confirmation as a verification method | None |
| An SOS with no GPS fix at all is placed at the centre of the resident's barangay, with no accuracy | It still reaches the board (FR8); the dispatcher calls back for the spot | Mention in Ch 3 |
| Server report limit: 5 per hour by capture time, and at most 10 received per hour | Offline backlogs arrive in bursts; the second cap stops back-dated capture times from getting around the limit | Provisional; A3 configuration later |
| DBSCAN's 60-minute window counts from capture time, not upload time | A report made offline belongs to the time it was made (NFR1) | Mention in Ch 3 |
| The resident's chosen type is kept apart from the classifier's suggestion (`reported_type` vs `category`); clusters use the classifier's when it exists | Keeps the classifier's output measurable for Chapter 4 | None |
| Applying the part 5 migrations did not reload the demo data | Joshua may have edited the live demo data | None |
| The phone's Hive boxes are encrypted (AES-256, key in Android secure storage) | They hold SOS locations and household details (RA 10173) | Mention in Ch 3 security |
| "Internet" means the S.A.G.I.P. server answers (auth health check every 20 s and on network changes); otherwise a mobile network counts as SMS only, nothing as no signal | Plan 7.6: do not trust the network type | None |
| Until Phase 5, the real app says records wait for internet instead of promising SMS or relay | Screens must not promise tiers that are not built | None |
| Records made in the same instant keep the order they were saved | Capture order must hold (NFR1) | None |
| Responder status changes are applied on screen at once and sent in order; a change the server refuses shows in the queue as not accepted | Responders must work offline (FR13) | None |
| A job that disappears from the server while the phone was working on it stays with the "reassigned or closed" banner until the responder sets Available | The responder must see why the job went away | None |
| The unit's position is sent every 15 s while online, even when it has not moved | The dashboard marks positions older than 2 minutes as stale | None |
| `compileSdk` 37 for the mobile app | `permission_handler_android` needs it | None |
| Sign-in codes go through Supabase's Send SMS hook to our `send-sms` Edge Function, which uses Semaphore's OTP route | One SMS provider for codes and broadcasts (Semaphore, FR6); Supabase has no built-in Semaphore option | Mention in Ch 3 |
| Without a Semaphore key, the hook sends nothing and keeps the message with the code in `sms_log` for an hour | The demo can sign residents in before the Semaphore account exists | None |
| `sms_log` holds full numbers and has no client access; the function's console output masks numbers | RA 10173 (NFR4) | None |
| The road graph is bundled in both apps as a 0.9 MB asset instead of downloaded from Storage | Responders can route with no signal (FR13); no download step or server cold start | Plan 10.2 said Storage; describe in Ch 3 |
| Graph area: the City of Manila plus 1.5 km, OSM drivable roads, kept to the largest strongly connected part | Stations and routes cross the city line; every intersection must reach every other | Mention in Ch 3 |
| Edge weight = length / speed per road class (motorway 60, trunk 40, primary 35, secondary 30, tertiary 25, unclassified 20, residential 15, living street 10 km/h); OSM maxspeed ignored | Provisional until MDRRMD's dispatch records (Table 3.1 item 2) allow tuning | Resolves plan Q19 as travel time; fix Ch 1 and Figure 1.2b wording |
| A point joins the graph at its nearest intersection within 1 km, with a straight access leg at 15 km/h; farther points fall back to straight-line estimates | Simple and fast; incidents in alleys are still routed to the nearest road | Mention in Ch 3 |
| The responder's phone runs Dijkstra itself from every new position; the route sent at dispatch is the record and a fallback | Re-routing works offline and follows the unit (FR13) | Plan said Dijkstra runs on the dashboard side; update Ch 3 |
| `assign_unit` gained an optional `p_route`; calls without it still work | Keeps the dashboard and the phone in step without a second call | None |
| Dijkstra timings: at most one logged run per job and kind a minute from each app; the server keeps at most 120 a minute per account | Suggestions recompute whenever a unit moves; one sample a minute is enough for Chapter 4 | Describe the measurement in Ch 4 |
| The priority score is computed when the board is read (in `incident_board`), not stored on insert and update | Waiting time adds points every minute, so a stored score goes stale; the dashboard ranks locally with the same weights between refreshes | Plan 10.1 said on insert and update; describe in Ch 3 |
| Priority weights are settings an admin changes on A3; each has a range (for example the mock-location penalty cannot become a bonus) and High stays at or below Critical | Placeholders until the MDRRMD SOP; no code change needed when it arrives | Mention in Ch 3 |
| Responders and residents cannot read the settings | They do not rank incidents | None |
| A4 times come from the incident timeline (dispatch = received to first assignment; response = received to on scene; travel = assigned to on scene); periods are rolling (last 24 hours, 7 days, 30 days) | The system's own records, comparable across periods; Objective 1's baseline from MDRRMD compares against these definitions | Define the measures in Ch 3 and 4 the same way |
| Units are retired, never deleted | Their dispatches and completion reports stay in the records (NDRRMC reports, analytics) | None |
| Retiring a unit takes its responders off it; a restored unit starts Available with no job | A responder's phone must not act for a unit that is out of service | Confirm with MDRRMD |
| Tier 2 text format `SAGIP1 SOS <id> <lat>,<lng> <accuracy> <time> <flags> <crc>`, CRC-16/CCITT-FALSE; the sender's number identifies the resident (no name or resident id in the text) | Short (about 85 characters, one SMS), versioned, checked; privacy (RA 10173) | Describe in Ch 3 (plan section 11) |
| An SOS texted from an unknown number still reaches the board (not account-verified, nearest barangay); the app's later copy attaches the resident | FR8: an SOS is never hidden; residents may text from another SIM | Mention in Ch 3 |
| The phone texts only the SOS (not details, reports, or responder updates), once, then still sends it over the internet when it can | SMS costs the resident load; the internet copy completes the record | Confirm with the team |
| The reply to the resident is returned by `sms-intake` for the gateway to send from its SIM; Semaphore only if `SMS_ACK_VIA_SEMAPHORE=true` | Plan: acknowledgement from the gateway SIM; Semaphore sender names cannot receive replies (Q30) | None |
| Tier 2 sends directly with SEND_SMS (sideloaded APK, plan Q29) | No user action needed during an emergency | Decide Q29 formally; Google Play would not allow it |
| Staff accounts are created by admins in the database (`admin_create_staff` writes `auth.users`), with a temporary password shown once | No Edge Function or service-role key needed; the same path the demo accounts used | Describe in Ch 3 |
| Deactivating an account bans the login, ends its sessions, and makes every role check ignore it at once | Access must stop immediately, not when the token expires | None |
| A suspended resident cannot send crowd reports, but an SOS still arrives (not account-verified) | FR8, life first; abuse control for reports only | Confirm with MDRRMD |
| Admins cannot deactivate, demote, or reset their own account on A1 | Prevents locking yourself out; own password changes on D11 | None |
| G2 appears only when a session ends without signing out; signing in returns to the same page | Plan 7.4 G2 | None |
| The web form is a second entry point of `apps/dashboard` with its own saved session (`sagip-webform-auth`) | Plan section 1; on a shared address it never picks up or signs out a dispatcher's session | None |
| New numbers can create an account on the web form (name, barangay, terms); `WEBFORM_REGISTRATION=false` turns it off | The plan's suggestion for Q13; FR15 targets residents who have not installed the app | **Decide Q13**; describe in Ch 3 |
| The hourly report limit is one setting (`reports.per_hour`) for the app and the web form together | The same account must not get around the limit by switching channels; A3 sets it (plan 7.4) | Mention in Ch 3 |
| On W2 nothing is sent until the resident chooses a location (browser, map pin, or barangay); the pin is grey until then | The map's starting view must never be sent as a hazard's location | None |
| The web draft lives in the browser's local storage per account and is removed when the report is sent or the resident signs out | Plan 7.2 ("draft kept in the browser"); shared computers (RA 10173) | Mention in Ch 3 |
| A web report keeps the time Send was first pressed and its id when sent again after a lost connection; a refusal by the server drops that time | Stored once, with the time it was made (NFR1); an old time must not keep a draft rate-limited | None |
| W3 lists the account's reports from both channels, each labelled | The hourly count covers both, so the list should too (the plan said web reports) | None |
| The resident's number on W1 stays in the page and is never put in the address bar | Browser history and shared computers (RA 10173) | None |
| Alert thresholds: rainfall 15 and 30 mm/hr, wind signal 1 and 3, storm surge 1.1 and 2.1 m (warning and critical) | PAGASA's heavy rainfall warning levels and storm surge risk bands; A3 changes them | **Provisional; confirm with MDRRMD** (FR5) |
| The threshold engine runs in the database (a trigger on `weather_alert`); it alerts when a hazard's level changes and expires the earlier alert | One place for the rule whatever inserts readings (PAGASA feed, simulation); residents never see two alerts for the same hazard | Describe in Ch 3 (FR5) |
| The very first reading only sets the baseline | Loading the demo data (one reading plus its own sample alerts) must not raise duplicates | None |
| Automatic alerts carry S.A.G.I.P.'s own wording with the PAGASA reading in it | PAGASA gives readings, not text for residents; the wording must be reviewed | **MDRRMD should review the six texts** |
| Simulated alerts (demo data and simulation mode) are shown in the apps and never texted or posted | A demo or UAT run must not text residents or post on Facebook | Mention in Ch 3 |
| Channel switches apply at once; a switched-off channel is logged as "off" for each later alert | The log must explain why an alert did not go out on a channel (FR6) | None |
| The hotline and the SMS gateway number are A3 settings read through `client_config()`, which needs no sign-in | No rebuild when MDRRMD provides the numbers; the sign-in screens show the hotline; both are public numbers | Mention in Ch 3 |
| The phone keeps the last copy of the two numbers | An SOS by SMS needs the gateway number exactly when there is no data (NFR1) | None |
| No data retention setting yet | What is removed and when (SMS log, old incidents) is a privacy and reporting decision, not a default | **Decide with MDRRMD** (RA 10173) |
| Alert texts: one SMS per resident (160 characters, cut at a word), to registered residents of the affected barangays, with a daily cap set on A3 (500 by default) | Each text costs credit (plan section 12: a spending cap); a long alert must not cost two | **Confirm the cap with MDRRMD**; mention in Ch 3 (FR6) |
| The sender claims deliveries before sending; a run that dies leaves them "sending" and they are taken again after 10 minutes | Two calls must never text the same alert twice; a crash must not lose an alert (a rare double send is the lesser harm) | None |
| Push and Facebook deliveries are logged as "not set up" rather than left waiting | The log must say plainly that nothing went out on those channels | None |
| Dispatchers can issue advisories and end alerts, not only admins | They watch the weather page during an event and FR6 is a dispatch duty; every one is audited with who sent it | Mention in Ch 3 (FR6, FR14) |
| PHIVOLCS, PAGASA, and EFCOS notices can be relayed by hand from D10, labelled with their source | No confirmed feed yet (plan Q35); FR14 is an advisory relay, so a person passing it on meets it until an ingest exists | Ch 3 should say the relay can be manual |
| An advisory is reviewed before it is sent, and cannot be edited afterwards (end it and issue a new one) | A broadcast cannot be recalled from phones; the log must show exactly what went out | None |
| Snackbars are 360 px wide at the bottom centre | A full-width one covered the drawer's "Assign" button for 4 s after "Mark verified" (found in the browser check) | None |

---

## Where we are against the plan (as of 2026-09-30)

| Milestone (plan section 2) | Date | State |
|---|---|---|
| M0: requests sent, accounts created | Oct 4 | Repo, GitHub, and Supabase done. Teammate requests (MDRRMD data, UAT slots, Semaphore, gateway hardware, phone list) not started as far as this file knows. |
| M1: design complete, five flows clickable, **scope checkpoint** | Oct 18 | Dashboard done (and already on Supabase, ahead of plan). Mobile app: every Tier 1 and Tier 2 screen built on mock data (Sep 30). Left: hallway test, fixes, and the scope checkpoint. |
| M2: online SOS to dispatch to resolve loop | Nov 1 | Dashboard half works on Supabase; needs the mobile SOS and responder side. |
| M3: feature freeze | Nov 15 | Dijkstra done (Sep 30) and DBSCAN done in the database. Classifier, LSTM + KDE, offline tiers 2 and 3, feeds not started. |

## Next steps (in order)

Joshua decided on 2026-09-30: **functions first, UI polish later**, once the whole system works. The order:

1. **Part 5, Phase 2 gaps:** done (database side of the mobile app, 87-check RLS test, Supabase repositories). Joshua: run `select public.reset_demo_data();` to load the new sample data.
2. **Part 6, Phase 3 and the first half of Phase 5:** done (the mobile app on Supabase with `.env`, the Hive offline queue, real GPS, the signal check, real permission prompts, the Send SMS hook). Joshua: deploy `send-sms` and switch Phone sign-in on (`supabase/README.md`).
3. **Part 7:** push notifications (FCM), responder background GPS, rescue confirmations.
4. **Phase 4 algorithms:** Dijkstra done (road graph, suggestions, routes on dispatch, phone navigation, timing log); priority score in the database with A3 weights done. Left: the classifier and LSTM + KDE when the Data role's datasets arrive.
5. **Phase 5 second half and Phase 6:** SMS fallback done in code (the gateway SIM and deploying `sms-intake` wait for Joshua and the team); BLE relay, PAGASA and PHIVOLCS feeds, Semaphore broadcasts, Facebook posting.
6. **Tier 3 on Supabase:** A1 accounts, A2 resources, A3 (all but data retention), A4 analytics, D11, G2, and the web form W1 to W3 done. The alert sender is written (not deployed) and advisories can be issued and ended from D10. Next in order: the incident type classifier, D8 forecast scaffolding, A5/A6 NDRRMC reports, then the forecast pipeline with clearly labelled sample data.
7. Later, when everything works: Joshua's UI review of both apps (including his dashboard UI changes), widget gallery, hallway test, CI.

## Not done yet (full list)

**Joshua + Claude (code)**
- Mobile app: widget gallery, SMS tier 2, BLE, offline map tiles, push notifications (see the apps/mobile status above)
- Dashboard: admin pages A5, A6 (NDRRMC reports) are placeholders; A3 lacks only the data retention period; D8 forecast is a placeholder; new-SOS sound; widget gallery
- Supabase: all 897 barangays with boundaries, device tokens, evacuation centers (Q38), configuration and priority-rule tables, Edge Functions (SMS intake, Semaphore alerts, PAGASA ingest, FCM), storage buckets
- Algorithms: TF-IDF classifier, LSTM + KDE forecast, RAG report (proof of concept); tuning Dijkstra's road speeds with MDRRMD records; a travel-time penalty for flooded roads (plan 10.2 "Could")
- Offline: gateway hardware and a field test for Tier 2, BLE mesh relay (proof of concept), responder tile pre-download
- Self-hosted Manila map tiles (dev tiles come from tile.openstreetmap.org, allowed for light development only)
- CI's first run on GitHub (next push); admin sign-in and the audit log, crowd reports, units, and weather pages not yet browser-checked on Supabase

**Joshua (settings and decisions)**
- Resident sign-in by SMS code: the `send-sms` Edge Function is written and tested (part 6c). Joshua deploys it and switches Phone sign-in and the Send SMS hook on; the six steps are in `supabase/README.md` ("Turning on resident sign-in by SMS code"). Until the Semaphore account exists, the code is kept in `sms_log` for an hour.
- Firebase project for push notifications (FCM): needed for part 7, not yet.
- Run `select public.reset_demo_data();` in the Supabase SQL editor to load the part 5 sample data (alerts, forecasts, past rescues). It replaces the current demo data.
- Turn on leaked-password protection in Supabase (Authentication, then Passwords)
- Confirm the one-`staff`-table design against the thesis (plan Q8)
- Decide plan Q13 (creating an account on the web form; it is on by default) and where the web form is hosted
- Deploy `send-alerts` and add its Database Webhook when the Semaphore account exists (`supabase/README.md`); send one test alert to your own number first
- Confirm the alert thresholds and the six automatic alert texts with MDRRMD; enter the hotline and the gateway number on the Configuration page when they exist; decide the data retention rule
- Decide where each algorithm runs and which LLM provider RAG uses (plan section 6)
- The Supabase project sits in a personal org on the free tier; the plan wants a team-owned account and the paid tier from the pilot to the defense

**Teammates (long lead time, plan section 6).** Joshua asked on 2026-09-30 to check where each of these stands; they take weeks: the MDRRMD data letter, the 897 barangays with boundaries, the Semaphore account, the GSM modem, and the test phones.
- The full list of Manila's 897 barangays with districts and boundaries (for the pickers, the Manila check, and forecasts) **(Data)**
- MDRRMD data letter (unit roster, triage SOP, incident records, descriptions, NDRRMC templates); hotline number
- UAT slots for Nov 23 to 27 (3 admins, 16 field personnel, 31 residents); ISO/IEC 25010 questionnaire validated by Oct 30
- Semaphore account and sender name; GSM modem and SIM; list of test phones (need 3+ for BLE, one low-end Android 10)
- Shared task board and weekly sync; names on the Data, UAT, and Docs roles

## Commit history (what each commit contains)

| Commit | Date | What |
|---|---|---|
| `5da18c7` | 2026-09-30 | Workspace, shared package (theme, models, mock backend, DBSCAN, priority rules), and the dashboard on mock data |
| `1a25ba5` | 2026-09-30 | Supabase: schema, RLS, dispatch functions, audit trigger, DBSCAN in SQL, demo data and tools, 29-check RLS test |
| `cd0822f` | 2026-09-30 | Supabase repositories in the shared package; dashboard runs on Supabase with `.env`; snackbar and location-text fixes |
| `cd75f29` | 2026-09-30 | Docs: Supabase setup, this file, conventions, plan ticks |
| `0ff9292` | 2026-09-30 | Docs: which tables to edit instead of the read-only views |
| `5822635` | 2026-09-30 | Docs: roadmap against milestones, full not-done list, commit history |
| `76380c2` | 2026-09-30 | Mobile app part 1: resident SOS on mock data (R1, R2, S6, SOS button, offline banner, mock phone backend); formatters and `LiveValue` moved to shared |
| `e10dbe1` | 2026-09-30 | Docs: mobile part 1 status, how to run, gotchas; VS Code launch entry for the mobile app |
| `bd7cf4b` | 2026-09-30 | Mobile app part 2: R3 Track responder, R4 Report a hazard, Back goes Home, delivery notices only after waiting offline; map base moved to shared |
| `6a20efb` | 2026-09-30 | Docs: mobile part 2 status, decisions, gotchas |
| `8ab2503` | 2026-09-30 | Shared: responder models and interface, mock responder, `UnitStatusControl`, `EtaHero`, bearing and distance helpers |
| `7f6b419` | 2026-09-30 | Mobile app part 3: responder screens F1 to F6, offer alert from any screen |
| `b519d13` | 2026-09-30 | Docs: mobile part 3 status, decisions, gotchas |
| `fe7fe7f` | 2026-09-30 | Shared: account models, `ResidentAccountRepository`, `PermissionService`, mock accounts, sample barangays |
| `b87d2b8` | 2026-09-30 | Mobile app part 4a: S1 splash and launcher icon, S2 welcome, S3 sign-in, S4 register, S5 code, S7 Me, personnel sign-in |
| `ac7ee05` | 2026-09-30 | Docs: mobile part 4a status, decisions, gotchas |
| `f7d8630` | 2026-09-30 | Shared: alert and forecast models, report stages, completed assignments, vulnerability and alert interfaces, mock alerts and history, `nearestBarangay`, `formatDate` |
| `08f6ad4` | 2026-09-30 | Mobile app part 4b: R5 location picker, R6 My activity, R7 and R8 alerts, R9 to R11 vulnerability profile, F7 history; placeholder page removed |
| `916e2a3` | 2026-09-30 | Docs: mobile part 4b status, decisions, gotchas |
| `b388e20` | 2026-09-30 | Supabase part 5: mobile schema, checked functions for every phone write, reads in the app's shapes, demo reset with past rescues, alerts, forecasts; RLS test at 87 checks |
| `a5495d0` | 2026-09-30 | Shared: Supabase repositories for the mobile app, `databaseRefusal`, `liveQuery.refreshOn`, tests on real server rows |
| `401e756` | 2026-09-30 | Docs: part 5 status, decisions, gotchas |
| `ba07a4c` | 2026-09-30 | Shared: offline outbox, sync engine, queue-backed repositories, saved copies, position sharing |
| `2e427d4` | 2026-09-30 | Mobile app part 6b: runs on Supabase with `.env`; encrypted Hive store, GPS, signal check, Android permissions; saved settings |
| `7501b70` | 2026-09-30 | Supabase part 6c: `send-sms` hook (Semaphore OTP or kept in `sms_log`), `sms_log` table, RLS test at 88 checks, README steps |
| `c777a62` | 2026-09-30 | Docs: part 6 status, decisions, gotchas |
| `c752459` | 2026-09-30 | CI workflow: formatting, translations, analyze, tests, Edge Function tests, key scan |
| `74e771b` | 2026-09-30 | Dijkstra: road graph build (`ml/road_graph`), bundled Manila graph, binary-heap Dijkstra, router, road-network unit suggestions in the dashboard, networkx-checked tests |
| `4aaf922` | 2026-09-30 | Docs: CI and Dijkstra status, decisions, gotchas |
| `68f4194` | 2026-10-01 | A3 Configuration: `app_setting` and `set_setting` (migration `configuration`, RLS test at 112), the score on `incident_board`, settings repositories, the A3 page with a live preview |
| `ab12ac6` | 2026-10-01 | Docs: A3 status, decisions, gotchas |
| `55ab889` | 2026-10-01 | A4 analytics: `analytics_report` (migration `analytics`, RLS test at 117), `buildAnalytics` for the mock, CSV export, the A4 page |
| `1ec22ca` | 2026-10-01 | Docs: A4 status, decisions, gotchas |
| `3f8711e` | 2026-10-01 | A2 resources: unit retirement and roster functions (migration `resources`, RLS test at 132), resource repositories, the A2 page |
| `bb21513` | 2026-10-01 | Docs: A2 status, decisions, gotchas |
| `2eb7628` | 2026-10-01 | Tier 2 SOS by SMS: SAGIP1 codec (Dart and TypeScript), sync engine SMS tier, Android `SmsManager` channel with an emulator integration test, `intake_sms_sos` and `submit_sos` changes (migrations `sms_intake`, `sms_gateway_provider`, RLS test at 141), `sms-intake` Edge Function, CI step |
| `2a91702` | 2026-10-01 | Docs: tier 2 status, decisions, gotchas |
| `ef8a515` | 2026-10-01 | D11 My account (password change, theme, shortcuts) and G2 Session expired |
| `9548196` | 2026-10-01 | A1 accounts: staff logins and resident suspensions (migration `accounts`, RLS test at 158), account repositories, the A1 page |
| `2fd995f` | 2026-10-01 | Docs: D11, G2, A1 status, decisions, gotchas |
| `f1ed1ca` | 2026-10-02 | Web form W1 to W3 (`lib/main_webform.dart`, `lib/src/webform/`), `WebReportRepository` (Supabase and mock), migration `web_form` (channel, `reports.per_hour`, `my_report_quota`; RLS test at 171), the report limit on A3, `SagipMark` and `reportStageVisual` moved to shared |
| `8a3efb1` | 2026-10-02 | Docs: web form status, decisions, gotchas |
| `3ea0472` | 2026-10-02 | The rest of A3 and the threshold engine: migration `alert_engine` (RLS test at 196), `AlertThresholds`, setting checks for numbers, switches, and text, alert log and simulation repositories, the A3 cards and unsaved-changes question, D10 levels and alert log, the hotline and gateway number from A3 in the phone and the web form |
| `6fe1178` | 2026-10-02 | Docs: alert engine and A3 status, decisions, gotchas |
| `73f5eed` | 2026-10-02 | The alert sender: migration `alert_sender` (RLS test at 206), the `send-alerts` Edge Function with Node tests, the SMS cap on A3, the sender's outcomes on D10, CI step |
| `0f20da5` | 2026-10-02 | Docs: alert sender status, decisions, gotchas |
| `6a0da61` | 2026-10-02 | Advisories from the dashboard: migration `advisories` (RLS test at 222), `AdvisoryRules`, `AlertLogRepository.issue` and `.end` (Supabase and mock), the D10 dialog with a review step, End alert, tests |
| `12013d1` | 2026-09-30 | Routes on dispatch records, `my_assignments` routes, `routing_run` timing log (migration `routing`, RLS test at 99); dashboard sends routes; phone navigation by road with the next turn |

`git log --oneline` shows newer commits; add a row here for each one.

---

## Gotchas

- Import `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`.
- In Git Bash, `cd` into paths with spaces needs quotes: `"/c/Users/Joshua Habana/Desktop/project-sagip"`.
- Artifact publishing needs the long Windows path (`C:\Users\Joshua Habana\...`), not the short `JOSHUA~1` form, or it is blocked by a permission rule.
- Widget tests: never `await` a repository stream inside `testWidgets`; read through the `ProviderContainer`. A bare `pumpAndSettle()` can hang for minutes; use `settle(tester)`.
- The test font is wider than Plus Jakarta Sans, so overflow errors show up in tests first. Fix them with `Flexible` + ellipsis, not by shrinking test text.
- `flutter gen-l10n` must be re-run after editing `app_en.arb`.
- intl puts U+202F before AM/PM; the font cannot draw it. `common/labels.dart` swaps it for U+00A0. Use those formatters, not `DateFormat` directly.
- Headless-Chrome automation (puppeteer) triggers a harmless engine error, `Cannot read properties of null (reading 'toString')` in Flutter's `KeyboardConverter`, because synthetic key events lack a key location. Real keyboards do not trigger it. Ignore it in automated browser runs.
- The map's dark and light looks come from color filters on OSM tiles (`map_parts.dart`, `_mutedDark` / `_mutedLight`); they go away when self-hosted styled tiles arrive.
- Supabase MCP: the local `supabase` connector answers "Resource has been removed". Use the claude.ai Supabase connector with `project_id: imssgenjfirpohkwxwbv`.
- Supabase `execute_sql` returns only the last statement's result. To run the pgTAP file there, collect each check into a temp table and end with a `do` block that raises an exception containing the results; the error also guarantees the whole run is rolled back. `supabase/tests/rls_test.sql` itself is plain pgTAP for `supabase test db`.
- New migrations applied through the MCP get a version stamped with the apply time. Rename the local file to match `list_migrations` so the CLI does not apply it twice.
- `package:supabase` also exports `AuthException`, which clashes with ours. Import it with `hide AuthException` plus a prefixed `show` import (see `supabase_repositories.dart`).
- Headless browser checks: Flutter's semantics tree could not be switched on by clicking `flt-semantics-placeholder`, so drive the page by coordinates and screenshots. Snackbars and toasts can sit on top of buttons; take a screenshot before clicking.
- Data streams restart when the signed-in account changes (`_forAccount` in `providers.dart`), so one account's data never stays in memory for the next.
- Long Python in a Bash heredoc can fail to parse here; write the script to the scratchpad and run the file.
- Android SDK is at `C:\Android\Sdk`. `sdkmanager` and `avdmanager` need `JAVA_HOME="/c/Program Files/Android/Android Studio/jbr"`. `flutter doctor` warns that some Android licenses are not accepted; builds still work. The first Gradle build takes about 5 minutes.
- Driving the emulator: `adb shell input tap X Y` and, for the SOS hold, `adb shell input swipe X Y X Y 2600` (same point, 2.6 s). Screenshots: `adb exec-out screencap -p > file.png`. The screen is 1080 x 2400.
- Widget tests of a hold: call `tester.pump()` once after `startGesture`, because an animation starts timing on the first frame after it starts.
- Snackbars queue: a second message waits until the first (4 s) is gone. Tests must pump past it.
- Tone tints (`p.critical.tint` and so on) are translucent. On cards over the page they look right; as a whole `Scaffold` background they show the black window through. Blend them: `Color.alphaBlend(tint, p.canvas)`.
- A `Row` inside a fixed-height box does not stretch its children vertically; use `crossAxisAlignment: CrossAxisAlignment.stretch` for segmented controls.
- An ARB key and a label helper with the same name clash: the generated getter wins (for example `outcome`, so the helper is `outcomeLabel`).
- In the emulator the text box does not open the on-screen keyboard (hardware keyboard), so `adb shell input keyevent 4` is a real Back press. Tap outside the field to close the keyboard instead.
- Map widgets need the Material bridge (`MaterialUiCompatibilityBridge` in `app.dart`) because flutter_map still uses `flutter/material.dart`. Tests override `mapTilesEnabledProvider` to false.
- `find.bySemanticsLabel` only finds labels on their own semantics node; give map markers `Semantics(container: true, label: ...)`.
- The app theme's `iconButtonTheme` greys every `IconButton`, including `IconButton.filled`. A filled icon button needs its own `style:` with a light foreground (see `HotlineCard`).
- When a button can disappear under the main button (Skip on S2), keep a fixed-height slot so the main button does not move under the thumb.
- Driving a live test from the emulator: `adb emu geo fix <lng> <lat>` sets the GPS (the default is California, which moves the unit on the live map); `adb shell svc wifi disable` and `svc data disable` cut the network. A live position update changes live data; note the unit's values first and restore them.
- `flutter_test` cannot override a provider twice; when a test swaps a few repositories, list its overrides instead of spreading `mockOverrides` and adding to it.
- In widget tests and in the app, repositories that merge server data with the outbox must turn server errors into "no data" (`nullOnError`), or an offline SOS would not show.
- Database functions refuse with short codes in the error message (`not_allowed`, `rate_limited`, ...); the REST API returns them in `message`, and `databaseRefusal()` maps them. Add new codes in both places.
- Security-definer functions called by signed-in users show up in the Supabase security advisor as warnings; for the app's write API that is intended (each checks the caller first).
- To see what a database function returns, run it in a transaction as the right user (`set local role authenticated`, `set local request.jwt.claims`) and end with a `do` block that raises the output; nothing is kept.
- Mobile widget tests build the backend with `withHistory: false` (the default) so lists start empty; pass `withHistory: true` to test R6 and F7 with sample rows. Many older tests expect Maria to have exactly one SOS.
- `tester.ensureVisible` did not bring the last alert card into the hit area inside the `RefreshIndicator` list; drag the list first (see `resident_extras_test.dart`).
- `StepState` is taken by Material's stepper; the shared timeline row is `TimelineStep` with `TimelineState` (`common/timeline.dart`).
- In a `Row`, a `Flexible` next to an `Expanded` splits the free space in half; cap the trailing widget's width instead (see `ActivityRow`).
- In flutter_map, handle only gesture moves in `onPositionChanged`; set the centre yourself when moving by code.
- An offered assignment opens F2 over any responder screen after about 10 s; widget tests that finish a job go back with `routerProvider.go`.
- Mobile widget tests override `welcomeSeenProvider` with `WelcomeDone` to skip S2, and sign in through the number and code (`MockMobileBackend.demoCode`) or the personnel form (`MockSeed.demoPassword`). Long lists build lazily: `scrollUntilVisible` before tapping.
- After a cold boot the emulator can show "System UI isn't responding"; tap Close app. The app's package is `ph.sagip.sagip_mobile` (for `adb shell monkey -p ... 1`).
- Edge Function helpers are plain TypeScript with no Deno-only imports so Node 24 can test them: `node --test supabase/functions/send-sms/sms.test.ts` (Node strips the types). Only `index.ts` uses `Deno`.
- The Send SMS hook signs each call (Standard Webhooks: `webhook-id`, `webhook-timestamp`, `webhook-signature`, secret `v1,whsec_...`). Deploy the function with `--no-verify-jwt`; the signature is the check.
- Rebuilding the road graph (`ml/road_graph/build_road_graph.py`) renumbers the intersections, because OSM changes daily: always run `make_reference.py` afterwards or the networkx test fails. osmnx caches downloads in `./cache` (git-ignored); run the scripts from a scratch folder or the repo root.
- Route providers are keyed by records (`({GeoPoint from, GeoPoint to, String incidentId})`) with `Provider.autoDispose.family`, so old positions' routes are dropped; `GeoPoint` has value equality, which the key relies on.
- Package assets load in widget tests and on the web (`rootBundle.load('packages/sagip_shared/assets/...')`); the dashboard and mobile widget tests really run Dijkstra.
- Browser checks without puppeteer: start `chrome.exe --headless=new --remote-debugging-port=9333`, serve `build/web` with `python -m http.server`, and drive it over the DevTools protocol from Node 24 (`Input.dispatchMouseEvent`, `Input.insertText`, `Page.captureScreenshot`, a `mouseWheel` event to scroll the drawer).
- The priority rules live in two places: `PriorityRules` (Dart) and `private.priority_breakdown` (SQL); `defaultPrioritySettings` mirrors the migration's seed rows. Change all three together; `priority_test.dart` and the RLS test check the same demo incidents (58 high, 88 critical).
- `not_found` from the database means a closed incident for dispatch actions but an unknown key for `set_setting`; `SupabaseSettingsRepository.set` maps it to `notFound` itself.
- A4's definitions live in `public.analytics_report` and `buildAnalytics` (the mock); `analytics_test.dart` and the RLS test check the same demo timeline (median dispatch 266 s, verification 138.5 s, response 842 s). Change both together.
- Browser downloads: `common/download.dart` picks `download_web.dart` (package:web) on the web and a stub elsewhere; the stub keeps `lastDownload` for widget tests.
- Dashboard widget tests: `ensureVisible` on a cell inside a `TableCard` scrolls the table sideways, not the page; for pages with several tables set a tall test window (`tester.view.physicalSize = Size(1440, 2400)`), and keep row actions narrow enough to fit 1440 px (icon buttons with tooltips). Read repository streams with `tester.runAsync(...)`; awaiting them directly hangs the test.
- ARB files are JSON: a key added twice is accepted silently (the last wins). Check for duplicates after adding many strings (a short Python `object_pairs_hook` check).
- Node's TypeScript type stripping does not allow constructor parameter properties (`constructor(readonly x)`); write the field out. Edge Function helpers that tests import must avoid Deno-only APIs.
- Checking the SMS channel on the emulator: `adb shell pm grant ph.sagip.sagip_mobile android.permission.SEND_SMS`, then `flutter test integration_test/sms_channel_test.dart -d emulator-5554`; `adb shell content query --uri content://sms/sent --projection address:body` shows the text.
- In one SQL statement, a subquery does not see rows a volatile function in the same statement inserted (statement snapshot). In the RLS test, call the function in one statement and check the row in the next.
- Supabase Auth: signing in again with `signInWithPassword` as the same user (to check a current password) fires a `signedIn` event for the same id, which `SupabaseAuthRepository` ignores; a `signedOut` event without a sign-out from the app is treated as an expired session (G2).
- In go_router's `redirect`, read the provider the router listens to (`ref.read(webUserProvider).value`), not a provider derived from it: inside the listener's refresh the derived one can still hold the old value, and the redirect silently keeps the old page.
- A page with one editor per settings group must ignore `app_setting` rows it has no field for; the priority editor crashed with a null check as soon as a second group (`reports.per_hour`) existed.
- A second web entry point: `flutter build web -t lib/main_webform.dart -o build/webform`. Both entry points share `web/index.html` and the ARB file.
- Checking browser geolocation with headless Chrome: `Browser.setPermission` (denied or granted) and `Emulation.setGeolocationOverride` over the DevTools protocol, in one connection (the override ends when the connection closes); `Network.emulateNetworkConditions` with `offline: true` fires the browser's offline event.
- `container.read` of a stream provider nobody watches returns loading; widget tests that read one across pages keep it alive with `container.listen` first.
- Adding a parameter to a database function makes a second function unless the old signature is dropped first (`drop function ...(old types)` then `create function`); grants must name the new signature.
- The Supabase connector can decline a SQL call that looks destructive when nobody is there to confirm it (a dry run that moved and renamed `reset_demo_data()` and added an automatic delete was declined). The answer was a migration that only adds things; anything that changes or removes existing objects or data waits for Joshua.
- `app_setting.value` can be a number, a switch, or text; `AppSetting.value` is an `Object` with `number`, `flag`, and `text` getters. Code that wants weights or thresholds must skip the other kinds (`if (s.value is num)`).
- The threshold rules live in two places: `AlertThresholds` and `weatherAlertText` (Dart) and `private.raise_weather_alerts` and `private.weather_alert_text` (SQL); `defaultOtherSettings` mirrors the seeded rows. `alert_engine_test.dart` and the RLS test run the same reading sequence. Change them together.
- A provider read once through the container (`ProviderScope.containerOf(context).read`) is still loading if nothing watched it before; the app listens to `clientConfigProvider` from its root widget so the hotline dialog has the value.
- go_router's `onExit` on a route inside the shell runs for `context.go` too; it is where A3 asks about unsaved changes. Editors report to a plain registry (`UnsavedChanges`), not provider state, because they update it from text listeners and `dispose`.
- A `Column` inside a `Card` centres its children unless it stretches them; list rows that are a padded `Column` need `crossAxisAlignment: CrossAxisAlignment.stretch` on the parent.
- An Edge Function's `index.ts` can be run under Node without Deno: set `globalThis.Deno = { env: { get }, serve: (h) => handler = h }` and replace `globalThis.fetch` before `await import('./index.ts')`, then call the handler with a `Request` (see `send-alerts/index.test.ts`).
- PostgREST returns nothing from an `rpc` call sent with `Prefer: return=minimal`; only use that header for inserts.
- Adding a value to a checked `status` column needs the Dart enum to know it before anything writes it: `enumFromJson` throws on a name it does not know.
- In a widget test, never `await` the mock directly (`await MockSettingsRepository(backend).set(...)`, `await repo.watchRecent().first`): the test body runs on a fake clock, the future never completes, and the run hangs with no error. Wrap it in `tester.runAsync(() => ...)`.
- Snackbars queue: a second one waits behind the first for 4 seconds. In a test, `await tester.pump(const Duration(seconds: 5))` before looking for the second.
- Run `flutter test` with `--timeout 90s` and write the output to a file (not through `grep | tail`), so a hung test shows up as "did not complete" instead of a silent wait.
- Mobile widget tests end with `finish(tester)`: it runs the simulated dispatcher to the end, disposes the backend, and unmounts, so no timers are left pending.

---

## Session log

### 2026-09-29: planning and wireframes (session f47c816b)
- Read the full thesis including all 30 figures. Wrote the implementation plan, revised it for a single developer.
- Decisions with Joshua: December defense, UAT before defense, OpenStreetMap, Riverpod + go_router, scope checkpoint on Oct 18.
- Published wireframes for the five flows (18 screens) on a Design canvas.

### 2026-09-30: workspace, shared package, dashboard (session f47c816b)
- Set up the git repo, pub workspace, `packages/shared`, and `apps/dashboard`; moved the design skill into `.claude/skills/`.
- Built the shared package (tokens, theme, models, repository interfaces, DBSCAN, priority rules, straight-line suggester, mock backend with simulation, shared widgets) and 35 tests. The contrast test caught four failing color pairs; fixed.
- Built the dashboard on the mock backend: sign in, shell, Command Board (map, list, drawer, assign, override), crowd reports, units, vulnerable list, weather, audit log, placeholders for the rest. 7 widget tests.
- Verified: `flutter analyze` clean in both packages, all 42 tests pass, `flutter build web --release` succeeds.
- Drove the real build in headless Chrome and fixed what the screenshots showed: pink roads on the dark map (now a muted blue-grey basemap), missing space in the clock, the new-SOS toast covering the Map/List switch, and the resident name being cut off. **Joshua has not reviewed it in person yet.**
- Wrote `docs/CONVENTIONS.md`, this file, and a root `.gitignore`; updated `CLAUDE.md` (points every session here; maps, Riverpod, material_ui, no co-author trailer) and ticked finished items in the plan.
- Not committed (no git identity configured; waiting for Joshua).

### 2026-09-30: Supabase backend and GitHub (session f47c816b)
- Built the hosted Supabase backend: 5 migrations (schema, access control, dispatch functions with audit and DBSCAN, demo data and tools, private RLS helpers), renamed locally to match the hosted versions. Staff accounts `dispatcher@sagip.test` and `admin@sagip.test` created in the SQL editor (password kept out of the repo).
- Added Supabase implementations of every repository interface in `packages/shared/lib/src/supabase/` (live queries: fetch, then refetch on realtime changes; database refusals mapped to `ActionRejected`). `main.dart` uses Supabase when `.env` is present, mock data otherwise. `ResidentRepository.logContactViewed` became `revealContact` (returns the number and audits it).
- Model changes: timestamps converted to local time, `UserRole.system`, numeric audit ids, numbers that arrive already masked.
- Browser check against the live project passed (details under Tests). It found two UI problems, both fixed: full-width snackbars covered the "Assign" button, and "from the sms" was lowercased (now a translatable phrase per channel).
- Added `supabase/tests/rls_test.sql` (29 checks, all passing on the hosted project, rolled back), `supabase/seed.sql`, `supabase/README.md`, and `.vscode/launch.json`.
- Created the public GitHub repo https://github.com/angrypoteto/project-sagip and pushed the first commit. Rewrote its author to angrypoteto's noreply email and force-pushed (with Joshua's approval) so GitHub credits angrypoteto instead of `habanajoshuaf-source`, which owns the Gmail address.
- Verified: `flutter analyze` clean in both packages; 39 shared tests and 7 dashboard tests pass; web build with the Supabase settings succeeds.
- Pushed commits `1a25ba5` to `0ff9292` to GitHub (Joshua approved). Joshua tested the dashboard on Supabase and confirmed it works, then tried editing `vulnerable_resident_list` in the Table Editor, which is a read-only view; `supabase/README.md` now says which tables to edit instead.
- Added the milestone table, the full "Not done yet" list, and the commit history to this file.

### 2026-09-30: mobile app part 1, resident SOS (session f47c816b)
- Plan approved by Joshua; test device: Android emulator. Created the `sagip_pixel` emulator (Android 15 image, WHPX acceleration).
- Created `apps/mobile` in the workspace (Android, minimum SDK 29, app name S.A.G.I.P.).
- Shared package: `SosButton`, `ConnectivityBanner`, `DeliveryBadge`; SOS and offline models; mobile repository interfaces; `MockMobileBackend`; formatters and `LiveValue` moved out of the dashboard.
- Mobile app: demo sign-in, role shells, offline banner, R1 Home and SOS, R2 SOS status with Add details, S6 queue sheet, a first S7 Me with demo tools, delivery notices.
- Found and fixed while testing: the release after a completed hold also opened the status screen (regression test added).
- Verified: analyze clean in all three packages; 53 shared, 7 dashboard, 4 mobile tests pass; checked on the emulator (details under Tests). Not checked: haptics on a real phone.

### 2026-09-30: mobile app part 2, tracking and reports (session f47c816b)
- Plan approved by Joshua. Built R3 Track responder and R4 Report a hazard on mock data; every Tier 1 resident screen now exists.
- Shared: `SagipTiles`, `MapCredit`, `manilaCenter`, `toLatLng` moved out of the dashboard (the dashboard's `SagipBaseMap` and `MapAttribution` now wrap them); `HazardReport`, `HazardReportRepository`, `ReportRejected`, `roughlyInsideManila`; responder position on `SosRequest`; the mock queues reports with SOS in capture order and drives R-03 toward the resident.
- Found and fixed on the emulator: Back on the Report tab closed the app (now returns to Home, with a regression test), the track card layout, and a delivery notice that covered the next form's Send button (notices now only for records that waited offline).
- Verified: analyze clean in all three packages; 56 shared, 7 dashboard, 6 mobile tests pass; emulator and dashboard browser checks (details under Tests).
- Noticed the live Supabase data had changed since the last reset (for example INC-0147 assigned to R-03), presumably Joshua testing; left as is.

### 2026-09-30: mobile app part 3, responder screens (session f47c816b)
- Plan approved by Joshua. Built F1 to F6 on mock data; every Tier 1 mobile screen now exists, and flow 4 runs end to end.
- Shared: `Assignment`, `CompletionReport`, `ResponderState`, `ResponderRepository`, the mock responder in `mock_responder.dart` (a `part` of the mobile mock so it shares the offline queue), `UnitStatusControl`, `EtaHero`, `GeoPoint.bearingTo`, `formatDistance`, `StraightLineSuggester.minutesFor`. The status screen's ETA card now uses `EtaHero`.
- Mobile: `OfferWatcher` opens F2 on any screen; weather strip, map markers, and a glove-sized counter moved to `common/`.
- Found and fixed on the emulator and in tests: unreadable F2 background, a message covering Accept, segment height, the arrival card, stale location sharing, and three narrow-screen overflows.
- Verified: analyze clean in all three packages; 59 shared, 7 dashboard, 8 mobile tests pass; emulator check (details under Tests).

### 2026-09-30: mobile app part 4a, sign-in and Me (session f47c816b)
- Joshua approved part 4 as 4a (S1 to S5, S7) then 4b (R5 to R11, F7), with a commit after each half.
- Shared: account models, `ResidentAccountRepository`, `PermissionService`, the mock accounts part, 10 sample barangays, 6 new tests.
- Mobile: splash, launcher icon (vector, red mark on white), welcome and permission steps, sign-in by number and code, register with a searchable barangay picker, the privacy notice (draft), the personnel sign-in form, and the full Me screen with theme choice and a data deletion request. The demo sign-in page is gone; its buttons live on S3 in demo mode only.
- Tests moved to the real flows (number and code for residents, the personnel form for responders).
- Found and fixed on the emulator: the S2 button jump, the grey hotline icon, and the swapped barangay label.
- Verified: analyze clean in all three packages; 65 shared, 7 dashboard, and 12 mobile tests pass; emulator check (details under Tests).

### 2026-09-30: mobile app part 4b, the rest of Tier 2 (session f47c816b)
- Part of the part 4 plan Joshua approved (4a then 4b, a commit after each half).
- Shared: alert, forecast, report stage, and completed-assignment models; `AlertRepository`, `VulnerabilityRepository`, `ResponderRepository.watchHistory()`; mock alerts and forecasts, consent and household changes, account-owned lists, an opt-in history seed; 12 new tests.
- Mobile: R5 location picker (and "Change" on R4), R6 My activity with the report sheet, R7 Alerts and forecast with the unread count on the tab, R8 alert detail, R9 vulnerability profile, R10 consent, R11 household member, F7 assignment history. The placeholder page and its strings are gone. The R2 timeline row moved to `common/timeline.dart` for reuse. 6 new widget tests.
- Found and fixed on the emulator: alert card overflow, the drifting unread dot, titles cut at half width, the inset withdraw link, and the pin offset (details under Tests).
- Verified: analyze clean in all three packages; 77 shared, 7 dashboard, and 18 mobile tests pass; emulator check. Every mobile Tier 1 and Tier 2 screen now exists on mock data.

### 2026-09-30: part 5, the database side of the mobile app (session f47c816b)
- Joshua decided: functions first, UI polish later. He noted the SMS hook, Firebase, and teammate items (recorded above), approved part 5, and approved pushing parts 4a and 4b (pushed `fe7fe7f` to `916e2a3`).
- Three migrations applied to the hosted project (`mobile_schema`, `mobile_actions`, `mobile_demo_data`; local files renamed to the hosted versions). The demo data was not reloaded (see Joshua's list).
- RLS test grown from 29 to 87 checks; all pass on the hosted project. Live REST check with a temporary responder account (deleted). Security advisor: only the expected warnings.
- Shared: Supabase mobile repositories and the remote calls part 6 will queue; tests parse real rows from the hosted functions.
- Verified: analyze clean in all three packages; 83 shared, 7 dashboard, 18 mobile tests pass. Not verified: resident phone sign-in (needs the Send SMS hook, part 6).

### 2026-09-30: part 6a and 6b, the offline outbox and the real app (session f47c816b, resumed)
- Joshua went to sleep and asked me to keep building whatever does not need his permission. Not done without him: pushing, Supabase dashboard settings, reloading the live demo data, lasting accounts.
- 6a (shared): the offline layer and its tests (15 new); `QueuedKind.sosDetails`; `AlertFeed` JSON; `LiveValue` exported. Committed `ba07a4c`.
- 6b (mobile): `hive_ce`, `supabase_flutter`, `geolocator`, `permission_handler`, `connectivity_plus`, `flutter_secure_storage`, `http`; device services in `lib/src/device/`; `liveOverrides`; `main.dart` switches on `.env`; Android permissions; saved settings; capability-aware wording; 2 new widget tests.
- Live check on the emulator against the hosted project with a temporary account and test incident, all removed afterwards (details under Tests).
- Verified: analyze clean in all three packages; 98 shared, 7 dashboard, 20 mobile tests pass.
- Next: 6c, the Send SMS hook Edge Function and the SMS log table, and the steps for Joshua to switch it on.

### 2026-09-30: part 6c, the Send SMS hook (session f47c816b, resumed)
- Still overnight on Joshua's instruction; same limits (no push, no dashboard settings, no demo reload, no lasting accounts, no Edge Function deploys).
- `supabase/functions/send-sms/`: the hook, its pure helpers, and 6 Node tests; `_shared/standard_webhooks.ts` checks the signature.
- Migration `sms_log` dry-run in a rolled-back transaction, then applied (renamed to `20260930150520_sms_log.sql`). RLS test at 88 checks, all passing on the hosted project (rolled back). Security advisor: only the expected items (the app's functions, and `sms_log` with no policies on purpose).
- `supabase/README.md`: the six steps for Joshua to switch resident sign-in on.
- Committed `7501b70`. Part 6 is done apart from Joshua's switch-on steps.
- Next: CI workflow, then Phase 4 Dijkstra.

### 2026-09-30: CI and Phase 4 Dijkstra (session f47c816b, resumed)
- Still overnight on Joshua's instruction; same limits (no push, no dashboard settings, no demo reload, no lasting accounts, no Edge Function deploys).
- CI workflow committed (`c752459`); each step checked locally; it first runs on GitHub at the next push.
- Built the Manila road graph with osmnx 2.1.1 (`ml/road_graph/`), bundled it in the shared package, and wrote Dijkstra with a binary heap, the router, and road-network unit suggestions. The test matches networkx on 50 random pairs. The dashboard ranks by road (`74e771b`).
- Migration `routing` dry-run with the full RLS test (99/99) in a rolled-back transaction, then applied (renamed to `20260930152606_routing.sql`). Routes go on dispatch records and to the responder's phone; every Dijkstra run is timed into `routing_run`. The phone routes by itself for F3 and F4 with the next turn (`12013d1`).
- Verified: analyze clean in all three packages; 125 shared, 7 dashboard, 20 mobile tests pass; the web release build loads the graph and ranks by road in headless Chrome (mock data). Not checked on the emulator: F4 with a road route (widget test only).
- Next: priority score in the database with a configuration table (A3).

### 2026-10-01: A3 Configuration and the priority score (session f47c816b, resumed)
- Still overnight on Joshua's instruction; same limits. The Android emulator's background task reached its time limit and was stopped; it was not needed for this work.
- Migration `configuration` dry-run with the full RLS test (112/112) in a rolled-back transaction, then applied (renamed to `20260930213044_configuration.sql`).
- Shared: settings model and repositories, rules from settings, the same checks as the database, new refusal kinds. Dashboard: the A3 page; the queue ranks with the saved weights. Committed `68f4194`.
- Verified: analyze clean in all three packages; 131 shared, 8 dashboard, 20 mobile tests pass. Not checked in the browser against Supabase: saving a weight (covered by the RLS dry run and the widget test).
- Next: A4 analytics.

### 2026-10-01: A4 analytics (session f47c816b, resumed)
- Migration `analytics` checked on the live data as the admin (rolled back), applied (renamed to `20260930214300_analytics.sql`), then the full RLS test passed 117/117 (rolled back).
- Shared analytics model, builder, and CSV; the A4 page with periods and export. Committed `55ab889`.
- Verified: analyze clean in all three packages; 138 shared, 9 dashboard, 20 mobile tests pass; web release build; A4 renders in headless Chrome on mock data. Not checked: A4 against Supabase in a browser (the function was run as the admin on live data).
- Next: A2 Resources.

### 2026-10-01: A2 resources (session f47c816b, resumed)
- Migration `resources` dry-run with the full RLS test (132/132, rolled back), then applied (renamed to `20260930215740_resources.sql`).
- Shared resource repositories (mock with the same rules; Supabase refreshes the roster after each change since `staff` is not on Realtime); the board and suggestions skip retired units. Dashboard A2 page. Committed `3f8711e`.
- Found while testing: the units table's row buttons were off-screen at 1440 px; they are now icon buttons with tooltips and tighter columns.
- Verified: analyze clean in all three packages; 141 shared, 10 dashboard, 20 mobile tests pass. Not checked in a browser.
- Next: D11 My account and G2 Session expired, then SMS tier 2 (format, parser, `sms-intake`).

### 2026-10-01: Tier 2 SOS by SMS (session f47c816b, resumed)
- The SAGIP1 text format with a CRC-16 checksum; the same codec in Dart and TypeScript with shared vectors.
- Migration `sms_intake` dry-run with the full RLS test (141/141, rolled back), applied (`20260930223414_sms_intake.sql`); `sms_gateway_provider` dry-run and applied (`20260930223708_sms_gateway_provider.sql`).
- Sync engine SMS tier; Android `SmsManager` channel; `SMS_GATEWAY_NUMBER` in the mobile `.env`; `sms-intake` Edge Function (not deployed). Committed `2eb7628`.
- Verified: analyze clean in all three packages; 150 shared, 10 dashboard, 20 mobile tests; 6 + 6 Node tests; the channel sent a real text on the emulator and the TypeScript decoder read it. Not verified: a gateway SIM forwarding to a deployed `sms-intake` (needs hardware and a deploy).
- Next: D11 My account and G2 Session expired, then A1 Accounts (with an Edge Function for creating logins), the web form W1 to W3.

### 2026-10-01: D11, G2, and A1 accounts (session f47c816b, resumed)
- D11 and G2 on the dashboard (`ef8a515`): `StaffSessionRepository` in the Supabase and mock auth.
- Migration `accounts` dry-run with the full RLS test (156 of 158 passed; the 2 failures were test statements reading rows inserted in the same statement, rewritten and re-checked), applied (`20260930230224_accounts.sql`). A1 page and repositories (`9548196`).
- Security advisor after the migration: only the expected items.
- Verified: analyze clean in all three packages; 153 shared, 13 dashboard, 20 mobile tests pass. Not checked in a browser against Supabase: creating a login and signing in with it (the SQL path is the one the demo accounts use).
- Next: W1 to W3, the resident web form for crowd reports.

### 2026-10-02: the resident web form W1 to W3 (session f47c816b, resumed)
- Migration `web_form` dry-run with the full RLS test in a rolled-back transaction (171 of 171), applied (`20261001081319_web_form.sql`). Security advisor afterwards: only the expected items.
- Shared: `WebReportRepository`, `ReportQuota`, the channel on `HazardReport`, `SupabaseWebFormBackend`, the mock's web path; `SagipMark` and `reportStageVisual` moved to shared.
- Dashboard package: the web form entry point and pages, the report limit card on A3, a fix so the priority editor ignores other setting groups (`f1ed1ca`).
- Verified: analyze clean in all three packages; 163 shared, 22 dashboard, 20 mobile tests pass; the release build of the web form checked in headless Chrome on sample data (see Tests). Not checked: the web form against Supabase, because resident sign-in needs the Send SMS hook (Joshua).
- Next: the rest of A3 (alert thresholds, SMS gateway number, channel switches, data retention, simulation mode).

### 2026-10-02: the rest of A3 and the threshold engine (session f47c816b, resumed)
- Migration `alert_engine`: a first version (which moved `reset_demo_data()` and deleted old SMS log rows automatically) had its dry run declined by the Supabase connector, so it was rewritten to only add things. Dry-run with the full RLS test in a rolled-back transaction (196 of 196), applied (`20261002085747_alert_engine.sql`). Afterwards, checked by query: RLS on every table, `sms_log` the only one without a policy, `client_config` the only function anon can call, every security-definer function with a fixed search path.
- Shared: settings of three kinds, `checkSetting` and `normalizeSetting`, `AlertThresholds`, the alert log, simulation, and client config repositories (Supabase and mock), `CachedClientConfig`, the SMS tier reading the gateway number when it sends.
- Dashboard: the A3 cards (`settings_cards.dart`), the unsaved-changes question, D10 with levels and the alert log. Phone and web form: the hotline and gateway number from A3 (`3ea0472`).
- Verified: analyze clean in all three packages; 178 shared, 26 dashboard, 21 mobile tests pass; A3 and D10 checked in headless Chrome on sample data (see Tests).
- Not done on purpose: the data retention period (needs a decision), the sender for queued deliveries (next), EFCOS.
- Next: the Semaphore broadcast sender for queued SMS deliveries (written and tested, not deployed), then A5/A6 and D8 scaffolding.

### 2026-10-02: the alert sender (session f47c816b, resumed)
- Migration `alert_sender` (service-role functions, the SMS cap setting, two more delivery statuses): its 10 checks ran with the migration in a rolled-back transaction, then it was applied (`20261002091507_alert_sender.sql`). Checked by query afterwards: none of the four functions is callable by clients.
- `send-alerts` Edge Function with 14 Node tests, including the real handler with stand-ins; CI step added. Not deployed.
- A3 gets the SMS alert limit; D10 shows counts and the sender's notes (`73f5eed`).
- Verified: analyze clean in all three packages; 178 shared, 26 dashboard, 21 mobile, 26 Node tests pass.
- Next: A5/A6 NDRRMC reports and D8 forecast scaffolding.

### 2026-10-02: advisories from the dashboard (session f47c816b, resumed)
- Migration `advisories` (`issue_alert`, `end_alert`, two audit actions): the full RLS test ran with it in a rolled-back transaction (222 of 222), then it was applied (`20261002092536_advisories.sql`).
- Shared: `AdvisoryRules`, `AlertLogRepository.issue` and `.end` (Supabase and mock). Dashboard: the "Issue an advisory" dialog with a review step and "End alert" on D10 (`6a0da61`).
- Browser check on sample data (headless Chrome): the dialog, chosen barangays, the review, the new row with Push and SMS waiting, the End confirmation, the Ended mark. Not checked on Supabase in a browser.
- Verified: analyze clean in all three packages; 184 shared, 28 dashboard, 21 mobile tests pass.
- Next: the incident type classifier (FR12).
