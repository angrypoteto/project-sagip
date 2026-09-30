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
- [ ] `EtaHero`, `UnitStatusControl`, `SagipMap` wrapper, widget gallery
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
- [ ] Responder and resident write paths (status updates, SOS insert, crowd report insert) for the mobile app
- [ ] SMS gateway, Semaphore, PAGASA feed, FCM (Edge Functions)
- [ ] Leaked-password protection is off (Supabase dashboard setting: Authentication, then Passwords); turn it on before the pilot

### apps/mobile (`sagip_mobile`), mock data
- [x] Demo sign-in (pick the resident or the responder account); the role picks the shell: resident Home, Report, Alerts, Me; responder Home, History, Me
- [x] Offline banner on every screen (SMS only, no signal, waiting count, sending, "Back online" for 4 s); tapping opens S6
- [x] R1 Home and SOS: greeting and barangay, PAGASA strip, SOS button with caption below it, GPS-off warning with Open settings, active SOS card, Report a hazard link
- [x] R2 SOS status: state heading and elapsed time, ETA card (unit, minutes), 9-step timeline, Add details sheet (type, people, extra help, note), location card, guidance, Call MDRRMD
- [x] S6 offline queue sheet: records with capture time and delivery badge, what happens next for the current signal, Try sending now, remove a rejected record
- [x] Delivery notice: "Your SOS from 3:42 PM was delivered." (in-app message; a system notification comes with FCM)
- [~] S7 Me: name, role, barangay, sign out, demo tools (signal and GPS switches); settings and privacy links not yet
- [x] R3 Track responder: full-screen map (shared `SagipTiles`), resident pin, responder marker gliding between updates, dashed line, one card with unit, status, ETA, "Updated 30 s ago" (stale after 2 min), offline "last known position", Call MDRRMD; opened from R2 once a unit is assigned
- [x] R4 Report a hazard: description, optional type, current location, on-phone checks (empty, no location, outside Manila, 5 per hour), saved on the phone and sent over internet only, confirmation with delivery badge, Send another
- [x] Android Back on another tab returns to Home instead of closing the app; tapping outside a text box closes the keyboard
- [ ] F1 to F6 responder screens (part 3); Alerts, responder Home and History tabs are placeholders
- [ ] R5 location picker ("Change" on R4), real barangay boundaries for the Manila check (part 4 and later)
- [ ] S1 splash (the launch screen is still the Flutter logo), S2 permissions, S3 to S5 real sign-in, R5 to R11, F7 (part 4)
- [ ] Cancel SOS (waits on plan Q10), nearest evacuation center card (waits on Q38 data), MDRRMD hotline number (Call MDRRMD says it is not set until `MDRRMD_HOTLINE` is provided)
- [ ] Hive queue, real GPS, SMS, and BLE (Phase 3 and 5); the mock keeps everything in memory, so closing the app clears it

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
- `packages/shared`: 56 passing (`flutter test`), including Supabase-shaped JSON, the mobile mock's offline rules (capture order, capture time kept, SMS and relay tiers, updates held while offline), and the SOS button (a tap never sends, a 2 s hold sends once, early release cancels, the release after a send does not also open), hazard reports (wait for internet while an SOS goes by SMS, delivered in capture order, the four on-phone checks), and the responder closing in with a falling ETA
- `apps/mobile`: 6 passing (the role picks the shell, and Back on another tab goes Home; online SOS to responder assigned; offline SOS by SMS, queue sheet, delivered on reconnect; add details; tracking before and after assignment; reporting: empty check, online, offline)
- Emulator check, part 2 (2026-09-30): R3 map with real OSM tiles, gliding marker, falling ETA, arrived state; R4 typed, sent, and delivered; Back from R3 to R2 to Home. Found and fixed: Back on the Report tab closed the app; "Track responder" competed with Call MDRRMD; the unit line wrapped; a repeated "arrived" message; the delivery notice covered the next form's Send button.
- Dashboard after the map base moved to shared: tests pass and a browser screenshot of the board looks the same.
- Emulator check (2026-09-30, `sagip_pixel`, driven with adb): sign-in, Home, a real 2.6 s hold with the progress ring, R2 timeline updating live to Verified, offline banner, offline SOS showing Sent by SMS, and the queue sheet all work. Found and fixed: the release after a completed hold opened R2 twice; a redundant badge on R2; the active SOS card's link crowded long states. Haptics not checked (the emulator does not vibrate); needs a real phone.
- `apps/dashboard`: 7 passing (sign-in, ranked queue, assign top unit, override needs a reason, admin pages hidden, admin audit log, offline disables actions)
- `supabase/tests/rls_test.sql`: 29 of 29 passing, run on the hosted project inside a rolled-back transaction (nothing was left behind)
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

Tap "Continue as resident" or "Continue as rescue personnel". Hold SOS for 2 seconds. In Me, the demo tools switch the signal (Internet, SMS only, No signal) and GPS. After an online SOS the simulated dispatcher verifies it after about 8 s, assigns R-03 after 14 s, and so on to Resolved after about 70 s.

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
| Mobile "was delivered" notices only for records that waited in the offline queue | A record sent at once already shows its status on screen; the extra notice covered the next form's Send button | Matches NFR1 wording |
| Hazard reports go over the internet only; SMS carries SOS only | Keeps the SMS gateway for emergencies | Confirm with the team |
| Report limit 5 per account per hour | FR15 and NFR7 give no number | Provisional; plan Q-list |
| The phone's Manila check is a rough box until barangay boundaries are bundled | R4 needs a check now; the server checks again (FR15) | None |
| Mock responder drives in a straight line from its station | Dijkstra routes come in Phase 4 | None |
| Snackbars are 360 px wide at the bottom centre | A full-width one covered the drawer's "Assign" button for 4 s after "Mark verified" (found in the browser check) | None |

---

## Where we are against the plan (as of 2026-09-30)

| Milestone (plan section 2) | Date | State |
|---|---|---|
| M0: requests sent, accounts created | Oct 4 | Repo, GitHub, and Supabase done. Teammate requests (MDRRMD data, UAT slots, Semaphore, gateway hardware, phone list) not started as far as this file knows. |
| M1: design complete, five flows clickable, **scope checkpoint** | Oct 18 | Dashboard done (and already on Supabase, ahead of plan). **Mobile app not started**: this is the biggest gap. |
| M2: online SOS to dispatch to resolve loop | Nov 1 | Dashboard half works on Supabase; needs the mobile SOS and responder side. |
| M3: feature freeze | Nov 15 | Algorithms (Dijkstra, classifier, LSTM + KDE), offline tiers, feeds not started. DBSCAN done in the database. |

## Next steps (in order)

1. **Mobile app, Tier 1, on mock data** (due M1, Oct 18). Parts 1 and 2 are done: every Tier 1 resident screen (R1 to R4, S6). Next: part 3, responder F1 to F6 (flow 4: receive, navigate with cached tiles, on scene, completion report, signal loss); then part 4, the Tier 2 screens (S1 to S5, S7, R5 to R11, F7).
2. **CI** (small): GitHub Actions running `flutter analyze` and `flutter test` on every push.
3. **Map spikes** (Phase 0, unblock later work): pick the self-hosted Manila tile source (Protomaps extract) and build the Manila road graph with `osmnx` for Dijkstra.
4. **Wire the five flows end to end on mock data**, fix the top issues from the hallway test, tag `phase1-design-complete`, and hold the Oct 18 scope checkpoint (record it in `docs/DECISIONS.md`).
5. Phase 2 and 3 on Supabase: SOS insert with the original capture timestamp, crowd reports, responder status updates (each with RLS tests), Hive offline queue.
6. Phase 4: Dijkstra (swap out `StraightLineSuggester`), the TF-IDF classifier, then LSTM + KDE and the forecast screen.

## Not done yet (full list)

**Joshua + Claude (code)**
- Mobile app: all responder screens, the Tier 2 screens, map wrapper, ETA hero, unit status control, Hive queue, real GPS, SMS, and BLE (see the apps/mobile status above)
- Dashboard: admin pages A1 to A6 (accounts, resources, configuration, analytics, NDRRMC reports) are placeholders; D8 forecast is a placeholder; D11 My account; G2 Session expired; W1 to W3 resident web form; new-SOS sound; widget gallery
- Supabase: resident and responder write paths, barangay boundaries, configuration and priority-rule tables, Edge Functions (SMS intake, Semaphore alerts, PAGASA ingest, FCM), storage buckets
- Algorithms: Dijkstra on the OSM road graph, TF-IDF classifier, LSTM + KDE forecast, RAG report (proof of concept)
- Offline: Hive queue, SMS fallback through the GSM gateway, BLE mesh relay (proof of concept), responder tile pre-download
- Self-hosted Manila map tiles (dev tiles come from tile.openstreetmap.org, allowed for light development only)
- CI; admin sign-in and the audit log, crowd reports, units, and weather pages not yet browser-checked on Supabase

**Joshua (settings and decisions)**
- Turn on leaked-password protection in Supabase (Authentication, then Passwords)
- Confirm the one-`staff`-table design against the thesis (plan Q8)
- Decide where each algorithm runs and which LLM provider RAG uses (plan section 6)
- The Supabase project sits in a personal org on the free tier; the plan wants a team-owned account and the paid tier from the pilot to the defense

**Teammates (long lead time, plan section 6)**
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
- In the emulator the text box does not open the on-screen keyboard (hardware keyboard), so `adb shell input keyevent 4` is a real Back press. Tap outside the field to close the keyboard instead.
- Map widgets need the Material bridge (`MaterialUiCompatibilityBridge` in `app.dart`) because flutter_map still uses `flutter/material.dart`. Tests override `mapTilesEnabledProvider` to false.
- `find.bySemanticsLabel` only finds labels on their own semantics node; give map markers `Semantics(container: true, label: ...)`.
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

