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
- [ ] `apps/mobile` (resident and responder Android app) not created
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
- [ ] `SosButton`, `ConnectivityBanner` (mobile), `DeliveryBadge`, `SyncQueueSheet`, `EtaHero`, `UnitStatusControl`, `SagipMap` wrapper, widget gallery
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
- `packages/shared`: 39 passing (`flutter test`), including parsing of rows shaped like the Supabase views
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

**On mock data:** same emails, password `sagip-demo`. What the mock demo does by itself after sign-in:
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

1. **Mobile app, Tier 1, on mock data** (due M1, Oct 18): create `apps/mobile` (Android only), the `SosButton` (hold to send, cancel, tier states), and the resident screens R1 to R4 and S6 (flow 1: send an SOS and see it delivered), then the responder screens F1 to F6 (flow 4: receive, navigate, update status, complete).
2. **CI** (small): GitHub Actions running `flutter analyze` and `flutter test` on every push.
3. **Map spikes** (Phase 0, unblock later work): pick the self-hosted Manila tile source (Protomaps extract) and build the Manila road graph with `osmnx` for Dijkstra.
4. **Wire the five flows end to end on mock data**, fix the top issues from the hallway test, tag `phase1-design-complete`, and hold the Oct 18 scope checkpoint (record it in `docs/DECISIONS.md`).
5. Phase 2 and 3 on Supabase: SOS insert with the original capture timestamp, crowd reports, responder status updates (each with RLS tests), Hive offline queue.
6. Phase 4: Dijkstra (swap out `StraightLineSuggester`), the TF-IDF classifier, then LSTM + KDE and the forecast screen.

## Not done yet (full list)

**Joshua + Claude (code)**
- Mobile app: everything (resident, responder, SOS button, offline banner, delivery badge, sync queue, map wrapper, ETA hero, unit status control)
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
