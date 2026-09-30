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
| 2026-09-30 | f47c816b (resumed) | Part 6: offline outbox and sync engine (6a), mobile app on Hive, GPS, connectivity, permissions, and Supabase via `.env` (6b), SMS-code hook and end-to-end run (6c) | `packages/shared/lib/src/offline/` (new), `packages/shared/lib/src/models/`, `packages/shared/lib/src/supabase/`, `packages/shared/test/`, `apps/mobile/`, `supabase/functions/` (new) | in progress |

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
- [ ] `ml/` folder is empty
- [ ] CI (GitHub Actions running analyze and tests)

### packages/shared (`sagip_shared`)
- [x] Design tokens: `SagipColors` (with text-safe variants), `SagipSpace`, `SagipRadius`, `SagipMotion`
- [x] `SagipPalette` theme extension (tones for light and dark) and `SagipTheme.light/dark(SagipDensity)`
- [x] Plus Jakarta Sans bundled (`assets/fonts`, OFL license included); icons from `material_symbols_icons` (bundled, works offline)
- [x] Automated WCAG contrast audit: `test/contrast_test.dart`
- [x] Models: `Incident` (+ `IncidentEvent`), `CrowdReport`, `ResponseUnit`, `AppUser`, `Resident`, `VulnerableMember`, `UnitSuggestion`, `WeatherStatus`, `AuditEntry`, `GeoPoint` (haversine), all enums
- [x] Repository interfaces: auth, incidents, units, crowd reports, residents, weather, audit, connection
- [x] Algorithms: `dbscan()` (haversine, eps 50 m, minPts 3), `PriorityRules` (provisional weights), `StraightLineSuggester` (stand-in for Dijkstra)
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
- [x] Offline layer (`offline/`, part 6a): `OutboxEntry` and `LocalStore` (memory for tests, Hive in the app); `SyncEngine` (saved first, sent in capture order with a save-order tie-break, delivered only on server confirmation, refusals kept as rejected, network failures stop the run and retry with backoff, each account's records wait for that account, a cut-off send is retried after a restart, delivered records kept a day); `ServerSender`; `MobileServer` (implemented by `SupabaseMobileRemote`); `OutboxSosRepository`, `OutboxHazardReportRepository` (same phone checks as the mock), `OutboxResponderRepository` (queued changes shown at once, jobs cached for offline work, jobs the dispatcher closes flagged), `OutboxOfflineQueue`; saved copies for SOS, reports, unit, jobs, history, alerts (read marks kept offline), weather, and profile; `ResponderLocationSharer` (every 15 s while online, plus a heartbeat when standing still); the signed-in account saved for offline restarts
- [ ] Widget gallery
- [ ] Dijkstra over the OSM road graph (plan 10.2)
- [ ] Incident type classifier (plan 10.4), LSTM + KDE (plan 10.5), RAG (plan 10.6)

### supabase/ (hosted project `imssgenjfirpohkwxwbv`, see `supabase/README.md`)
- [x] Schema: staff, residents + vulnerable household members, units, incidents + timeline, crowd reports, dispatches, weather, audit log (5 migrations, applied)
- [x] Row Level Security on every table; clients get read-only grants; full contact numbers are hidden (masked column + audited `reveal_resident_contact`)
- [x] Every write is a checked database function: verify, SMS check, false report, confirm type, assign/reassign, resolve
- [x] Audit log written by a trigger on incident changes, plus the functions (FR11); rows made outside the app are logged as "System"
- [x] DBSCAN clustering of crowd reports in the database (`ST_ClusterDBSCAN`, eps 50 m, minPts 3, 60 min)
- [x] Realtime on incidents, timeline, crowd reports, units, weather, audit log, households
- [x] Demo data and tools (SQL editor only): `reset_demo_data()`, `demo_new_sos()`, `demo_add_crowd_report()`, `demo_advance()`, `create_staff_account(...)`
- [x] RLS test: `supabase/tests/rls_test.sql`, 29 pgTAP checks across anon, dispatcher, admin, responder, resident, and a signed-in account with no role
- [x] Mobile write paths and reads (part 5, 3 migrations): resident linking and registration, SOS (client UUID stored once, capture time kept, vulnerable household types, on the board at once), SOS details, crowd reports (Manila check, 5 an hour by capture time plus 10 received an hour), consent and household changes, data deletion requests, responder accept, arrive, on-scene check, status control, completion reports (resolve the incident, free the unit), position sharing, alert read state; reads in the app's model shapes; DBSCAN counts from capture time
- [x] New tables with RLS: `barangay` (10 samples), `completion_report`, `public_alert`, `alert_read`, `barangay_forecast`, `data_deletion_request`; view `my_alerts`; household members carry `member_id` in `resident_profile`
- [ ] Load the new sample data on the hosted project: run `select public.reset_demo_data();` (not run by the migration, so edits Joshua made are kept until he chooses)
- [ ] SMS gateway, Semaphore, PAGASA feed, FCM (Edge Functions)
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
- [ ] Real offline map tiles (F2/F3 progress is simulated), road routes and turn-by-turn (Dijkstra, Phase 4), a custom alert sound (FCM work)
- [ ] Real barangay boundaries for the Manila check and the picker's "Near ..." line (needs the Data role's boundary file)
- [ ] The welcome-seen flag and theme choice live in memory (Hive later); real texted codes need Supabase phone sign-in and the SMS hook (plan Q37); real permission prompts come with the real GPS, SMS, and BLE work
- [ ] Cancel SOS (waits on plan Q10), nearest evacuation center card on R7 (waits on Q38 data), a separate pin for a household member who lives elsewhere (needs a schema change, plan Q14), MDRRMD hotline number (Call MDRRMD says it is not set until `MDRRMD_HOTLINE` is provided)
- [x] The real app (part 6b): with `apps/mobile/.env` it runs on Supabase (`liveOverrides`), with an encrypted Hive store (AES key in Android secure storage), GPS through `geolocator` (keeps the last fix, flags mock locations), a signal monitor that checks the server answers (not just Wi-Fi), and real Android permission prompts on S2. Without `.env` it runs on sample data as before
- [x] Welcome-seen and theme saved on the phone
- [x] Screens never promise what the real app cannot do yet (`DeviceCapabilities`): offline banner and queue sheet say records are saved and sent when back online; the offline-map row on F3 is hidden
- [ ] SMS tier 2 and BLE tier 3 on the phone, real offline map tiles (Phase 5); resident sign-in on Supabase needs the Send SMS hook (part 6c)

### apps/dashboard (`sagip_dashboard`), runs on Supabase (with `.env`) or mock data
- [x] D1 Staff sign in (demo accounts shown only in mock mode)
- [x] Shell: top bar (PAGASA summary, live/offline indicator, clock, user menu with theme toggle and demo connection switcher), navigation rail (admin items hidden for dispatchers), offline/reconnecting banner, new-SOS toast
- [x] D2 Command Board map view (incidents, units, unverified reports, layers, legend, zoom)
- [x] D3 list view (table)
- [x] D4 Incident drawer: status, rank, wait timer, type confirm/override, verification (call resident, SMS check, mark verified, mark false report), resident and vulnerable household, cluster reports, priority breakdown, suggested units, assigned unit, reassign, mark resolved, timeline
- [x] D5 Override dialog (reason required) and "Choose another unit" dialog
- [x] D6 Crowd reports: confirmed clusters with 50 m ring, unverified singles
- [x] D7 Units table with status counts and stale-GPS flag
- [~] D8 Forecast: placeholder page (waits on LSTM + KDE)
- [x] D9 Vulnerable Resident Priority List (numbers masked; revealing is audited)
- [x] D10 Weather and advisories (PAGASA simulated; EFCOS and PHIVOLCS marked not connected)
- [ ] D11 My account
- [~] A1 Accounts, A2 Resources, A3 Configuration, A4 Analytics, A5/A6 NDRRMC reports: placeholder pages (Tier 3, built on Supabase in Phase 3)
- [x] A7 Audit log
- [x] G1 Not found (also used to hide admin pages from dispatchers)
- [ ] G2 Session expired
- [ ] W1 to W3 resident web form (Tier 3)
- [ ] New-SOS sound (toast exists, no sound yet)
- [ ] Enter key on the queue (arrow keys and Esc work)
- [ ] List view: at 1440 px the table scrolls sideways; consider hiding low-value columns when the drawer is open
- [ ] Crowd reports map: the 50 m ring is only a few pixels at city zoom; add a count marker for clusters

### Tests (last run 2026-09-30)
- `packages/shared`: 98 passing (`flutter test`), including the offline layer (capture order, notices only after waiting, network failure and retry, refusals kept, other accounts wait, restart recovery, JSON round trip, SOS shown at once offline then as the server has it, report checks and the hourly limit, merging, a responder job worked offline end to end, a closed job, saved copies, alert read marks offline, position sharing with heartbeat), the server rows above, part 4b (alerts newest first and unread count, forecast by barangay and none for some, refresh offline keeps the saved time, add, edit, remove, withdraw and consent, changes need internet, history seed visible to Maria only, delivered reports go to Checking, a map pin is sent without accuracy, responder history with a report waiting, nearest barangay, JSON for the new models), accounts (number formats, unknown number, the 3-a-minute code limit, register then verify, deletion request, permission states), Supabase-shaped JSON, the mobile mock's offline rules (capture order, capture time kept, SMS and relay tiers, updates held while offline), and the SOS button (a tap never sends, a 2 s hold sends once, early release cancels, the release after a send does not also open), hazard reports (wait for internet while an SOS goes by SMS, delivered in capture order, the four on-phone checks), the responder closing in with a falling ETA, and the mock responder (offer and accept, refused status moves, completion makes the unit available, offline updates and the report sent in capture order)
- `apps/mobile`: 20 passing (an offline SOS through the real outbox behind the real screens: honest offline banner, waiting count, delivered on reconnect with the notice; saved theme and welcome; R6 history and the report sheet; R6 empty for a new account; R7 unread count, reading two alerts, forecast, offline line; R9 to R11 validation, add, remove, withdraw, consent again, offline; R5 by search and by barangay offline, sent without accuracy; F7 week filters and a report saved on the phone; first run: welcome steps then sign-in by code, wrong code; bad and unknown numbers and the offline notice; register with the barangay picker; Me: theme, deletion request, sign-out warning; the role picks the shell, and Back on another tab goes Home; online SOS to responder assigned; offline SOS by SMS, queue sheet, delivered on reconnect; add details; tracking before and after assignment; reporting: empty check, online, offline; responder offer, accept, navigate, arrive, on scene, report; responder offline report and the required reason)
- Live check on the emulator against the hosted project (2026-09-30, part 6b): real Android prompts on S2 (location, notifications, SMS, nearby devices); resident sign-in shows "Couldn't send or check the code right now" (the SMS hook is not on yet) and sends nothing; a temporary responder account for R-12 signed in; a test incident assigned by SQL reached the phone over Realtime within seconds and opened F2; Accept reached the server (incident and unit En route, timeline and audit log under the responder's name); with the network off, Mark on scene, the on-scene check, and the completion report waited on the phone ("3 waiting to send", unit shown Available); on reconnect all three reached the server in order with their offline capture times (report made 22:54:15, received 22:54:50); History showed the job; restarting the app offline kept the account and the saved unit and weather. Found and fixed: the sign-in error was cut to one line (inputs now wrap errors to three lines); position sharing only sent on movement, so a parked unit went stale (heartbeat added). Cleaned up afterwards: test incident, its timeline, dispatch, report, audit rows, and the account deleted; R-12's position restored.
- Emulator check, part 4b (2026-09-30): Alerts with the unread count (3, then 2 after reading), alert detail, forecast, My activity (SOS and Reports), the report sheet, Vulnerability profile, the add-member checks, R5 with real map tiles (pin stays centred, coordinates and "Near" update while dragging), and F7 in light and dark. Found and fixed: the alert card header overflowed at phone width with long dates (time moved under the title); the unread dot moved sideways between cards; report and history titles were cut at half the row because the chip took half; "Withdraw consent" was inset from the text; the R5 pin tip sat about 4 dp above the chosen point. Checked by widget tests only: R5 offline, R10, the offline states. Not checked: dark theme on every new screen (History was checked).
- Emulator check, part 4a (2026-09-30): launcher icon, S2 steps with Allow, S3, S5 with the demo code landing on Home ("Hi, Maria"), S4, and Me all render. Found and fixed: the main S2 button jumped down when Skip disappeared after Allow; the hotline call icon was grey on blue (the app theme greys every icon button, even filled ones); the register barangay row read "Choose your barangay / Barangay" (label and hint swapped). Not checked on the emulator: the staff form, dark theme on every new screen.
- Emulator check, part 3 (2026-09-30): the full responder job on Android: F1, the F2 alert, accept, F3 with the map progress reaching "saved", F4 following the unit to the scene, Arrived, F5, F6, back to Available. Found and fixed: the F2 background was a translucent tint over the black window (unreadable); status segments did not fill their height; a leftover message covered Accept; arrival showed "Head north · 0 m" and "1 min"; location sharing went stale after the drive. The arrival card fix is checked by the widget test, not re-run on the emulator.
- Emulator check, part 2 (2026-09-30): R3 map with real OSM tiles, gliding marker, falling ETA, arrived state; R4 typed, sent, and delivered; Back from R3 to R2 to Home. Found and fixed: Back on the Report tab closed the app; "Track responder" competed with Call MDRRMD; the unit line wrapped; a repeated "arrived" message; the delivery notice covered the next form's Send button.
- Dashboard after the map base moved to shared: tests pass and a browser screenshot of the board looks the same.
- Emulator check (2026-09-30, `sagip_pixel`, driven with adb): sign-in, Home, a real 2.6 s hold with the progress ring, R2 timeline updating live to Verified, offline banner, offline SOS showing Sent by SMS, and the queue sheet all work. Found and fixed: the release after a completed hold opened R2 twice; a redundant badge on R2; the active SOS card's link crowded long states. Haptics not checked (the emulator does not vibrate); needs a real phone.
- `apps/dashboard`: 7 passing (sign-in, ranked queue, assign top unit, override needs a reason, admin pages hidden, admin audit log, offline disables actions)
- `supabase/tests/rls_test.sql`: 87 of 87 passing (part 5 added 58: SOS stored once with capture time and vulnerable types, the mock-location flag hidden from residents, Manila check, hourly limit, report stages, consent and household, linking and registering by phone, another resident's SOS hidden and untouchable, responder accept/arrive/on-scene/report/status/position, alerts and read state, forecasts, audit entries under the responder's name, anon and private-helper privileges), run on the hosted project inside a rolled-back transaction
- Live API check (2026-09-30): a temporary responder account called the new functions through the REST API (the app's path): reads returned JSON, refusals came back as codes (`no_assignment`, `not_allowed`), anon was denied. The account was deleted afterwards and nothing was changed.
- `packages/shared`: `supabase_mobile_json_test.dart` parses rows captured from the hosted functions into the app's models, and checks the refusal mapping
- Browser check on Supabase (2026-09-30, headless Chrome, 1440 x 900): dispatcher sign-in; board loaded from the database; realtime delivered a new SOS toast and a new DBSCAN cluster without reload; "Show number" revealed the full number; "Mark verified" and "Assign" worked; all five actions appear in `audit_log` under R. Santos. Demo data reset afterwards. Not yet checked in the browser: admin sign-in and the audit log page on Supabase, crowd reports, units, and weather pages on Supabase.
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

**Mobile app on Supabase:** copy `apps/mobile/.env.example` to `.env` (same values as the dashboard's), then `flutter run --dart-define-from-file=.env` in `apps/mobile`, or "Mobile (Supabase)" in VS Code. Responders sign in with a staff account (`create_staff_account(..., 'responder', 'unit-r03')`). Residents need the Send SMS hook first (part 6c).

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
| Snackbars are 360 px wide at the bottom centre | A full-width one covered the drawer's "Assign" button for 4 s after "Mark verified" (found in the browser check) | None |

---

## Where we are against the plan (as of 2026-09-30)

| Milestone (plan section 2) | Date | State |
|---|---|---|
| M0: requests sent, accounts created | Oct 4 | Repo, GitHub, and Supabase done. Teammate requests (MDRRMD data, UAT slots, Semaphore, gateway hardware, phone list) not started as far as this file knows. |
| M1: design complete, five flows clickable, **scope checkpoint** | Oct 18 | Dashboard done (and already on Supabase, ahead of plan). Mobile app: every Tier 1 and Tier 2 screen built on mock data (Sep 30). Left: hallway test, fixes, and the scope checkpoint. |
| M2: online SOS to dispatch to resolve loop | Nov 1 | Dashboard half works on Supabase; needs the mobile SOS and responder side. |
| M3: feature freeze | Nov 15 | Algorithms (Dijkstra, classifier, LSTM + KDE), offline tiers, feeds not started. DBSCAN done in the database. |

## Next steps (in order)

Joshua decided on 2026-09-30: **functions first, UI polish later**, once the whole system works. The order:

1. **Part 5, Phase 2 gaps:** done (database side of the mobile app, 87-check RLS test, Supabase repositories). Joshua: run `select public.reset_demo_data();` to load the new sample data.
2. **Part 6 (next), Phase 3 and the first half of Phase 5:** the mobile app on Supabase (switched by `.env`, like the dashboard), resident sign-in by SMS code through the Send SMS hook, the Hive offline queue, real GPS, live tracking; an SOS runs phone to dashboard to responder phone to resolved (M2 demo, Nov 1).
3. **Part 7:** push notifications (FCM), responder background GPS, rescue confirmations.
4. **Phase 4 algorithms:** priority score in the database, Dijkstra on the OSM road graph (build the graph with `osmnx`); then the classifier and LSTM + KDE when the Data role's datasets arrive.
5. **Phase 5 second half and Phase 6:** SMS fallback and gateway, BLE relay, PAGASA and PHIVOLCS feeds, Semaphore broadcasts, Facebook posting.
6. **Tier 3 on Supabase:** admin A1 to A6, D11, G2, web form W1 to W3.
7. Later, when everything works: Joshua's UI review of both apps (including his dashboard UI changes), widget gallery, hallway test, CI.

## Not done yet (full list)

**Joshua + Claude (code)**
- Mobile app: widget gallery, Hive queue, real GPS, SMS, BLE, offline map tiles, push notifications (see the apps/mobile status above)
- Dashboard: admin pages A1 to A6 (accounts, resources, configuration, analytics, NDRRMC reports) are placeholders; D8 forecast is a placeholder; D11 My account; G2 Session expired; W1 to W3 resident web form; new-SOS sound; widget gallery
- Supabase: all 897 barangays with boundaries, device tokens, evacuation centers (Q38), configuration and priority-rule tables, Edge Functions (SMS intake, Semaphore alerts, PAGASA ingest, FCM), storage buckets
- Algorithms: Dijkstra on the OSM road graph, TF-IDF classifier, LSTM + KDE forecast, RAG report (proof of concept)
- Offline: Hive queue, SMS fallback through the GSM gateway, BLE mesh relay (proof of concept), responder tile pre-download
- Self-hosted Manila map tiles (dev tiles come from tile.openstreetmap.org, allowed for light development only)
- CI; admin sign-in and the audit log, crowd reports, units, and weather pages not yet browser-checked on Supabase

**Joshua (settings and decisions)**
- Resident sign-in by SMS code: Supabase needs something to send the text. The plan is Supabase's Send SMS hook calling a small Edge Function that sends through Semaphore. Until the Semaphore account exists, that function saves the code so the demo can show it. Joshua switches Phone sign-in and the hook on in the Supabase dashboard (Claude gives the exact clicks in part 6). Noted 2026-09-30.
- Firebase project for push notifications (FCM): needed for part 7, not yet.
- Run `select public.reset_demo_data();` in the Supabase SQL editor to load the part 5 sample data (alerts, forecasts, past rescues). It replaces the current demo data.
- Turn on leaked-password protection in Supabase (Authentication, then Passwords)
- Confirm the one-`staff`-table design against the thesis (plan Q8)
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
