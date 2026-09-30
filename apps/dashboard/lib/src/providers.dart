import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart';
import 'package:sagip_shared/sagip_shared.dart';

// ---------------------------------------------------------------------------
// Repositories. Each throws until main.dart overrides it, so screens can only
// reach data through these interfaces (CLAUDE.md architecture rule).
// ---------------------------------------------------------------------------

Never _missing(String name) => throw UnimplementedError(
  '$name is not configured. Override it in main.dart (mock or Supabase).',
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => _missing('AuthRepository'),
);
final incidentRepositoryProvider = Provider<IncidentRepository>(
  (ref) => _missing('IncidentRepository'),
);
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => _missing('UnitRepository'),
);
final crowdReportRepositoryProvider = Provider<CrowdReportRepository>(
  (ref) => _missing('CrowdReportRepository'),
);
final residentRepositoryProvider = Provider<ResidentRepository>(
  (ref) => _missing('ResidentRepository'),
);
final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => _missing('WeatherRepository'),
);
final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => _missing('AuditRepository'),
);
final connectionMonitorProvider = Provider<ConnectionMonitor>(
  (ref) => _missing('ConnectionMonitor'),
);

/// Only set when running on mock data. Screens use it for the demo scenario
/// switcher; everything else goes through the repositories above.
final mockBackendProvider = Provider<MockBackend?>((ref) => null);

/// Whether map tiles load from the network. Tests turn this off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// Overrides that run the dashboard on [backend] (Phase 1).
///
/// With [demoTools] off, the scenario switcher and the live simulation are
/// hidden (tests use this to stay deterministic).
List<Override> mockOverrides(MockBackend backend, {bool demoTools = true}) => [
  mockBackendProvider.overrideWithValue(demoTools ? backend : null),
  authRepositoryProvider.overrideWithValue(MockAuthRepository(backend)),
  incidentRepositoryProvider.overrideWithValue(MockIncidentRepository(backend)),
  unitRepositoryProvider.overrideWithValue(MockUnitRepository(backend)),
  crowdReportRepositoryProvider.overrideWithValue(
    MockCrowdReportRepository(backend),
  ),
  residentRepositoryProvider.overrideWithValue(MockResidentRepository(backend)),
  weatherRepositoryProvider.overrideWithValue(MockWeatherRepository(backend)),
  auditRepositoryProvider.overrideWithValue(MockAuditRepository(backend)),
  connectionMonitorProvider.overrideWithValue(MockConnectionMonitor(backend)),
];

/// Overrides that run the dashboard on the Supabase project (see
/// docs/CONVENTIONS.md, "Supabase").
List<Override> supabaseOverrides(SupabaseBackend backend) => [
  authRepositoryProvider.overrideWithValue(backend.auth),
  incidentRepositoryProvider.overrideWithValue(backend.incidents),
  unitRepositoryProvider.overrideWithValue(backend.units),
  crowdReportRepositoryProvider.overrideWithValue(backend.crowdReports),
  residentRepositoryProvider.overrideWithValue(backend.residents),
  weatherRepositoryProvider.overrideWithValue(backend.weather),
  auditRepositoryProvider.overrideWithValue(backend.audit),
  connectionMonitorProvider.overrideWithValue(backend.connection),
];

// ---------------------------------------------------------------------------
// Live data.
// ---------------------------------------------------------------------------

final currentUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchUser(),
);

/// Data streams restart when the signed-in account changes, so nothing one
/// account loaded under its access rules stays in memory for the next one.
/// Signed out, they wait.
Stream<T> _forAccount<T>(Ref ref, Stream<T> Function() open) {
  final account = ref.watch(currentUserProvider.select((u) => u.value?.id));
  return account == null ? const Stream.empty() : open();
}

final activeIncidentsProvider = StreamProvider<List<Incident>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(incidentRepositoryProvider).watchActive(),
  ),
);

final unitsProvider = StreamProvider<List<ResponseUnit>>(
  (ref) => _forAccount(ref, () => ref.watch(unitRepositoryProvider).watchAll()),
);

final crowdReportsProvider = StreamProvider<List<CrowdReport>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(crowdReportRepositoryProvider).watchRecent(),
  ),
);

final weatherProvider = StreamProvider<WeatherStatus>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(weatherRepositoryProvider).watchCurrent(),
  ),
);

final vulnerableResidentsProvider = StreamProvider<List<Resident>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(residentRepositoryProvider).watchVulnerable(),
  ),
);

final residentProvider = StreamProvider.family<Resident?, String>(
  (ref, id) => _forAccount(
    ref,
    () => ref.watch(residentRepositoryProvider).watchResident(id),
  ),
);

final auditLogProvider = StreamProvider<List<AuditEntry>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(auditRepositoryProvider).watchRecent()),
);

final linkStateProvider = StreamProvider<LinkState>(
  (ref) => ref.watch(connectionMonitorProvider).watch(),
);

/// True when actions can be sent. Unknown counts as online so the first
/// frame is not greyed out.
final isOnlineProvider = Provider<bool>(
  (ref) =>
      (ref.watch(linkStateProvider).value ?? LinkState.live) == LinkState.live,
);

/// Ticks every second for wait timers and the top-bar clock.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});

/// Ticks every 15 seconds. The queue re-sorts on this, not every second, so
/// rows do not jump while the dispatcher reads them.
final slowClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 15), (_) => DateTime.now());
});

// ---------------------------------------------------------------------------
// Rules and derived data.
// ---------------------------------------------------------------------------

final priorityRulesProvider = Provider<PriorityRules>(
  (ref) => const PriorityRules(),
);

/// Ranks units by road travel time (Dijkstra over the bundled OSM road
/// graph, plan 10.2), falling back to straight-line estimates for units the
/// graph cannot place or when the graph fails to load.
final unitSuggesterProvider = Provider<UnitSuggester>(
  (ref) => RoadNetworkSuggester(loadManilaRouter),
);

/// The Triage Queue in priority order (FR2).
final triageQueueProvider = Provider<AsyncValue<List<Incident>>>((ref) {
  final rules = ref.watch(priorityRulesProvider);
  final now = ref.watch(slowClockProvider).value ?? DateTime.now();
  return ref
      .watch(activeIncidentsProvider)
      .whenData((incidents) => rules.order(incidents, now));
});

/// Looks up one active incident by id; null if it has closed.
final incidentByIdProvider = Provider.family<Incident?, String>((ref, id) {
  final incidents = ref.watch(activeIncidentsProvider).value ?? const [];
  for (final i in incidents) {
    if (i.id == id) return i;
  }
  return null;
});

final unitsByIdProvider = Provider<Map<String, ResponseUnit>>((ref) {
  final units = ref.watch(unitsProvider).value ?? const [];
  return {for (final u in units) u.id: u};
});

/// Ranked Available units for an incident (FR3).
final suggestionsProvider = FutureProvider.family<List<UnitSuggestion>, String>(
  (ref, incidentId) {
    final incident = ref.watch(incidentByIdProvider(incidentId));
    final units = ref.watch(unitsProvider).value ?? const <ResponseUnit>[];
    if (incident == null) return Future.value(const []);
    return ref.watch(unitSuggesterProvider).suggest(incident, units);
  },
);

// ---------------------------------------------------------------------------
// UI preferences.
// ---------------------------------------------------------------------------

/// The command center defaults to dark (design skill).
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
