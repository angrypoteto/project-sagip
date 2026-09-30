# Coding conventions

Rules every session follows in this repo. CLAUDE.md has the architecture rules; this file has the concrete patterns. If something here conflicts with the thesis, stop and ask.

## Versions (as of 2026-09-30)

| Tool | Version | Note |
|---|---|---|
| Flutter | 3.47.2 (stable) | Dart 3.13.2 |
| Material widgets | `material_ui` 1.5 | **Import `package:material_ui/material_ui.dart`, never `package:flutter/material.dart`.** Material moved out of the Flutter SDK into this package. |
| State management | `flutter_riverpod` 3.4 | Decided 2026-09-29 |
| Routing | `go_router` 18 | Decided 2026-09-29 |
| Maps | `flutter_map` 8.3 + `latlong2` | OpenStreetMap, decided 2026-09-29 |
| Icons | `material_symbols_icons` | Use `Symbols.<name>_rounded` only |

`flutter_map` still imports the old `flutter/material.dart`, so `app.dart` wraps the app in `MaterialUiCompatibilityBridge` (deprecated, with an `ignore` comment). Remove the bridge when flutter_map moves to `material_ui`.

## Workspace

One pub workspace (root `pubspec.yaml`). Members use `resolution: workspace`. Run `flutter pub get` once at the root.

```
packages/shared   sagip_shared: theme, models, repository interfaces, algorithms, mock backend, shared widgets
apps/dashboard    sagip_dashboard: dispatcher and admin web app
apps/mobile       not created yet (resident and responder Android app)
```

When `apps/mobile` is created, add it to the root `workspace:` list.

## State management (Riverpod 3)

- **Repositories are providers that throw until overridden.** `apps/dashboard/lib/src/providers.dart` declares one provider per repository interface. `main.dart` overrides them all with `mockOverrides(backend)` in Phase 1; Phase 3 adds `supabaseOverrides(...)`. Screens never create repositories themselves.
- Live data is a `StreamProvider` over a repository `watch*` stream (for example `activeIncidentsProvider`).
- Derived data is a plain `Provider` (for example `triageQueueProvider`, `incidentByIdProvider`).
- UI state that outlives a widget is a `Notifier` + `NotifierProvider` (for example `themeModeProvider`, `queueFilterProvider`). Do not use the legacy `StateProvider`.
- The open incident and the map/list view live in the **URL**, not in a provider (`/board?incident=INC-0147&view=list`), so links and the back button work.
- `clockProvider` ticks every second (timers); `slowClockProvider` ticks every 15 s (queue ordering, so rows do not jump).

## Routing (go_router)

- All paths are constants in `Routes` (`apps/dashboard/lib/src/router.dart`).
- Auth and role checks live in the single `redirect`. Signed-out users go to `/sign-in?from=<path>`. Admin paths start with `/admin/`; dispatchers who open one get the Not found page (admin pages are hidden, not disabled).
- Pages use `NoTransitionPage` (dashboard has no page transitions).

## Folder structure (feature first)

```
lib/
  main.dart                 overrides + runApp
  src/
    app.dart                MaterialApp.router, themes, l10n
    router.dart             Routes + GoRouter
    providers.dart          repository providers + shared derived providers
    common/                 helpers used by several features (labels, actions, async_body)
    l10n/                   app_en.arb + generated app_localizations*.dart
    features/<feature>/     one folder per area (board, crowd_reports, units, ...)
```

Keep widgets small. Anything used by two features moves to `common/`; anything the mobile app will also need moves to `packages/shared`.

## The four states

Every screen handles loading, empty, error, and offline:

- Use `AsyncBody` (`common/async_body.dart`) for loading, empty, and error. It keeps showing the last good data during a refresh.
- Offline is shown once by the shell (`_ConnectionBanner`). Actions read `isOnlineProvider` and disable themselves, with a line of text saying why.
- Run actions through `runAction()` (`common/actions.dart`) so errors are shown the same way everywhere.

## Design system

- Follow `.claude/skills/sagip-flutter-design/SKILL.md`.
- Colors: `SagipPalette.of(context)` (tones: `critical`, `warning`, `success`, `info`, `onScene`, `neutral`, each with `fill`, `text`, `tint`). Never hard-code hex values in widgets.
- Spacing, radius, motion: `SagipSpace`, `SagipRadius`, `SagipMotion`.
- Status is always color + icon + text: use `SagipChip.status(visual: incidentStatusVisual(...))`.
- Numbers that change (timers, ETAs, counts) use `FontFeature.tabularFigures()`.
- `packages/shared/test/contrast_test.dart` checks WCAG AA for every text color pair. If you change a color, that test must still pass.

## Text and l10n

- Every visible string is in `apps/dashboard/lib/src/l10n/app_en.arb`. Regenerate with `flutter gen-l10n` (run inside `apps/dashboard`).
- Enum labels are in `common/labels.dart` (`l10n.incidentStatus(...)`, `l10n.incidentType(...)`, and so on).
- Sentence case, plain words, active voice. Errors say what happened and what to do.

## Models

- Immutable classes in `packages/shared/lib/src/models/` with `fromJson`/`toJson`. JSON keys match the database columns from thesis Figure 3.6 (snake_case).
- Domain values use the exact CLAUDE.md vocabulary (`pendingVerification`, `enRoute`, ...).

## Tests

- `packages/shared/test`: pure logic (DBSCAN, priority, mock backend rules, contrast).
- `apps/dashboard/test`: widget tests that drive the real UI on the mock backend.
- In widget tests: override `mapTilesEnabledProvider` to false, override both clocks with a fixed time, create `MockBackend(latency: Duration.zero)`, and pass `demoTools: false`. Use `settle(tester)` (5 s limit) instead of bare `pumpAndSettle`. Read state through `container.read(...)`; do not `await` repository streams inside `testWidgets`, because they can hang under the fake clock.
- Before calling a task done: `flutter analyze` (zero issues) and `flutter test` in each package you touched.

## Commits

- Format: `type(scope): summary`, for example `feat(dashboard): triage queue list view`.
- **No `Co-Authored-By` trailer and no AI attribution line** (the user's explicit instruction).
- Only commit when the user asks.
