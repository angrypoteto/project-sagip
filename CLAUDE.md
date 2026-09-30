# CLAUDE.md — Project S.A.G.I.P.

Read this before doing anything in this repo. The full plan is in `docs/SAGIP-IMPLEMENTATION-PLAN.md`; the thesis (Chapters 1–3) is the source of truth for requirements. Requirement IDs FR1–FR15 and NFR1–NFR7 come from that document.

**Start every session by reading `docs/PROGRESS.md`.** It lists what is built, what is not, and which areas other sessions have claimed. Follow its session protocol: claim your area before editing, never edit files another session has claimed, and update the file (status, session log, active work) before you stop. Code patterns are in `docs/CONVENTIONS.md`.

## What this is

Project S.A.G.I.P. (Smart AI-Integrated Geospatial Incident Platform) is a capstone emergency response system for the Manila City Disaster Risk Reduction and Management Department (MDRRMD). It lets residents send SOS signals and hazard reports, lets dispatchers triage and assign rescue units, guides responders with routes, forecasts 72-hour barangay-level flood/fire/storm-surge risk, and keeps SOS working offline.

Four roles, each a separate account:

| Role | Surface | Main job |
|---|---|---|
| Resident | Android app; web form for crowd reports only | SOS (app only), crowd reports, vulnerability profile, alerts, track responder |
| Field Rescue Personnel | Android app | Receive assignment, navigate, update status, file completion/damage report |
| Dispatcher | Web dashboard | Triage Queue: verify, prioritize, assign units |
| Administrator | Web dashboard | Dispatcher powers (oversight) + accounts, resources, analytics, audit log, NDRRMC reports |

## Current phase

**Phase 1: frontend design with mock data.** Build screens against repository interfaces backed by `Mock*Repository` classes. See the plan for the screen inventory and the five flows to prototype. The web dashboard is done for Phase 1 and can also run on the hosted Supabase project through `Supabase*Repository` classes (Joshua asked for this on 2026-09-30; see `supabase/README.md`). New screens still start on mock data; do not wire other apps to Supabase unless the task says so. `apps/mobile` runs on mock data; all Tier 1 screens are built (resident R1 to R4 and S6, responder F1 to F6), plus sign-in and Me (S1 to S5, S7); the rest of Tier 2 (R5 to R11, F7) is next (details in `docs/PROGRESS.md`).

## Stack

- Flutter / Dart (null safety) for the Android app and the web dashboard
- Supabase: PostgreSQL + PostGIS, Auth, Realtime, Storage, Edge Functions
- Hive for the offline queue on device
- Python + TensorFlow for LSTM training; TensorFlow Lite on device; scikit-learn for TF-IDF classifier, DBSCAN, KDE
- Semaphore SMS API (outbound broadcasts); GSM modem gateway (inbound SOS SMS)
- Maps: OpenStreetMap via `flutter_map` (decided 2026-09-29). Development uses public OSM tiles; switch to self-hosted Manila tiles before the pilot. Dijkstra runs on an OSM road graph.
- Material widgets come from the `material_ui` package (Flutter 3.47): import `package:material_ui/material_ui.dart`, never `package:flutter/material.dart`
- PAGASA, PHIVOLCS, EFCOS feeds; FCM push; MDRRMD Facebook Page posting

Mobile target is Android only (Android 10 minimum). iOS is out of scope.

## Repo layout

```
apps/mobile/        Resident + responder app (role decides the shell after login)
apps/dashboard/     Dispatcher + admin web dashboard
packages/shared/    Models, theme/design tokens, shared widgets, repository interfaces
supabase/           Migrations, seed data, Edge Functions, RLS tests
ml/                 Data prep notebooks, LSTM/KDE training, classifier, exported TFLite
docs/               Plan, conventions, decisions
```

If a folder doesn't exist yet, create it following this layout instead of inventing a new one.

## Commands

```bash
flutter pub get                          # in each app/package
flutter run -d chrome                    # dashboard on mock data
flutter run -d chrome --dart-define-from-file=.env   # dashboard on Supabase (in apps/dashboard; needs .env)
flutter emulators --launch sagip_pixel   # Android emulator for the mobile app
flutter run -d <android-device-id>       # mobile (in apps/mobile)
flutter analyze                          # must pass with zero issues before commit
flutter test                             # run tests for the package you touched
dart format .                            # format before commit
supabase start / supabase db reset       # local database (migrations + seed); CLI not installed yet
supabase test db                         # RLS test (supabase/tests/rls_test.sql)
select public.reset_demo_data();         # hosted project, SQL editor: reload the demo data
```

## Architecture rules

- UI never talks to Supabase, Hive, or HTTP directly. Widgets → state (providers/controllers) → repository interface → implementation (Mock, Supabase, Hive).
- Shared models live in `packages/shared` and are immutable, with `fromJson`/`toJson`.
- Every screen handles four states: loading, empty, error, offline.
- Keep widgets small; extract anything reused twice into `packages/shared`.
- State management and routing: Riverpod 3 + go_router 18 (decided 2026-09-29). Follow the patterns in `docs/CONVENTIONS.md`.
- Design and UI work must follow the `sagip-flutter-design` skill in `.claude/skills/`.

## Domain vocabulary (use these exact terms in code and UI)

- Incident status: `pendingVerification`, `unverified`, `confirmed`, `assigned`, `enRoute`, `onScene`, `resolved`
- Unit status: `available`, `enRoute`, `onScene` (FR9)
- Incident types: `flood`, `fire`, `medical`, `structural` (FR12)
- SOS = single-person rescue request (mobile only, never via web form). Crowd report = hazard report that needs DBSCAN corroboration (can come from web form).
- A single SOS appears on the board immediately as Pending Verification; it is never hidden while waiting (FR8).
- A single crowd report is never auto-confirmed; it needs a cluster (FR7, FR15).

## Algorithm parameters (from the thesis; do not change without team agreement)

- **LSTM:** 14-day window of daily features (rainfall total + max hourly, highest typhoon signal, max wind, storm surge level, prior-day incident count); predicts ≥1 incident in next 72 h. Layers 64 → 32, dropout 0.2, sigmoid output, class-weighted binary cross-entropy, Adam lr 0.001, batch 32, ≤100 epochs, early stopping patience 10, chronological 70/15/15 split.
- **KDE:** Gaussian kernel, haversine distance, bandwidth chosen from 100/200/300/400/500 m by 5-fold CV log-likelihood, 100 m grid averaged per barangay.
- **DBSCAN:** haversine, eps 50 m, minPts 3, reports from the preceding 60 minutes.
- **Dijkstra:** directed road graph, nodes = intersections, edge weight = estimated travel time. Use a binary-heap priority queue.
- **Classifier:** TF-IDF on word unigrams + bigrams, 4 labels.
- **Priority Queue:** ranks by severity, vulnerable status, and waiting time; rules come from MDRRMD SOP.

## Offline rules (NFR1, FR13)

- Every SOS, crowd report, and responder status update is written to the Hive queue first, then sent.
- Store the original capture timestamp; never overwrite it with upload time.
- Sync in captured order; mark as synced only after the server confirms; notify the user on delivery.
- Escalation for resident SOS: Tier 1 Hive → Tier 2 native SMS to gateway → Tier 3 BLE mesh relay.
- Responder app caches the current assignment and pre-downloads map tiles at dispatch time.

## Security and privacy (NFR4, Data Privacy Act RA 10173)

- Row Level Security on every table. No table ships without RLS policies and a test.
- Residents see only their own records; responders see only assigned incidents; the Vulnerable Resident Priority List is Admin + Dispatcher only.
- Get consent before saving a vulnerability profile.
- Never log names, phone numbers, or exact coordinates in console output or analytics.
- No secrets in the repo. Keys go in `.env` (git-ignored) or Supabase secrets. The Supabase service-role key never goes in client code.
- Every dispatch action, status change, and verification writes an audit log entry (FR11), preferably via database trigger.

## Scope guardrails

Do not build these unless the team explicitly adds them: multi-agency dispatch (BFP, PNP, Red Cross), resource inventory tracking (water levels, supplies), evacuation center management, relief goods, drones, satellite comms, earthquake/volcano forecasting (PHIVOLCS is advisory relay only), iOS.

Build-status promises to the panel: SOS/GPS, Command Board, realtime sync, Hive, SMS fallback + Semaphore, PAGASA, Dijkstra are fully implemented. DBSCAN and the vulnerable list use simulated input. LSTM+KDE is trained but uses a simulated live feed. BLE mesh and RAG are proof-of-concept.

## How to work in this repo

- For anything bigger than a small fix, write a short plan first (files to touch, approach, risks) and wait for approval.
- Keep changes small and focused on one task; don't refactor unrelated code.
- Run `flutter analyze` and relevant tests before saying a task is done. Say plainly if something is untested.
- Database changes only through new migration files in `supabase/migrations/`. Never edit an applied migration.
- When the thesis and the code disagree, stop and ask. Known inconsistencies are listed at the end of the plan.
- Commit messages: `type(scope): summary` (e.g., `feat(dashboard): triage queue list view`). No `Co-Authored-By` trailer or any other AI attribution line.
- UI text: English first, all strings in `l10n` files so Filipino can be added.

## Team

Proponents: Jennifer G. Maalat, Mark Christian Cacho, Joshua F. Habana, Arwind Jae M. Mendoza. Joshua is the only developer; the other three handle data, UAT, and documentation (plan section 3). Adviser: Prof. Ernanie M. Carlos Jr. Beneficiary: Manila City MDRRMD.
