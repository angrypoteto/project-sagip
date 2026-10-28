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
final staffSessionProvider = Provider<StaffSessionRepository>(
  (ref) => _missing('StaffSessionRepository'),
);
final incidentRepositoryProvider = Provider<IncidentRepository>(
  (ref) => _missing('IncidentRepository'),
);
final unitInventoryRepositoryProvider = Provider<UnitInventoryRepository>(
  (ref) => throw UnimplementedError('override unitInventoryRepositoryProvider'),
);
final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => _missing('UnitRepository'),
);
final crewRepositoryProvider = Provider<CrewRepository>(
  (ref) => _missing('CrewRepository'),
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
final reportRepositoryProvider = Provider<ReportRepository>(
  (ref) => throw UnimplementedError('override reportRepositoryProvider'),
);
final feedStatusRepositoryProvider = Provider<FeedStatusRepository>(
  (ref) => _missing('FeedStatusRepository'),
);
final forecastRepositoryProvider = Provider<ForecastRepository>(
  (ref) => throw UnimplementedError('override forecastRepositoryProvider'),
);
final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => _missing('AuditRepository'),
);
final connectionMonitorProvider = Provider<ConnectionMonitor>(
  (ref) => _missing('ConnectionMonitor'),
);
final routingLogProvider = Provider<RoutingLogRepository>(
  (ref) => _missing('RoutingLogRepository'),
);
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => _missing('SettingsRepository'),
);
final analyticsRepositoryProvider = Provider<AnalyticsRepository>(
  (ref) => _missing('AnalyticsRepository'),
);
final resourceRepositoryProvider = Provider<ResourceRepository>(
  (ref) => _missing('ResourceRepository'),
);
final safePlaceRepositoryProvider = Provider<SafePlaceRepository>(
  (ref) => _missing('SafePlaceRepository'),
);
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => _missing('AccountRepository'),
);
final alertLogRepositoryProvider = Provider<AlertLogRepository>(
  (ref) => _missing('AlertLogRepository'),
);
final simulationRepositoryProvider = Provider<SimulationRepository>(
  (ref) => _missing('SimulationRepository'),
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
List<Override> mockOverrides(MockBackend backend, {bool demoTools = true}) {
  // One timing log for Dijkstra runs and for A4's figures.
  final runs = MemoryRoutingLog();
  return _mockOverrides(backend, runs, demoTools: demoTools);
}

List<Override> _mockOverrides(
  MockBackend backend,
  MemoryRoutingLog runs, {
  required bool demoTools,
}) => [
  mockBackendProvider.overrideWithValue(demoTools ? backend : null),
  authRepositoryProvider.overrideWithValue(MockAuthRepository(backend)),
  staffSessionProvider.overrideWithValue(MockAuthRepository(backend)),
  incidentRepositoryProvider.overrideWithValue(MockIncidentRepository(backend)),
  unitRepositoryProvider.overrideWithValue(MockUnitRepository(backend)),
  crewRepositoryProvider.overrideWithValue(MockCrewRepository(backend)),
  unitInventoryRepositoryProvider.overrideWithValue(
    MockUnitInventoryRepository(backend),
  ),
  crowdReportRepositoryProvider.overrideWithValue(
    MockCrowdReportRepository(backend),
  ),
  residentRepositoryProvider.overrideWithValue(MockResidentRepository(backend)),
  weatherRepositoryProvider.overrideWithValue(MockWeatherRepository(backend)),
  feedStatusRepositoryProvider.overrideWithValue(
    MockFeedStatusRepository(backend),
  ),
  forecastRepositoryProvider.overrideWithValue(MockForecastRepository(backend)),
  reportRepositoryProvider.overrideWithValue(MockReportRepository(backend)),
  auditRepositoryProvider.overrideWithValue(MockAuditRepository(backend)),
  connectionMonitorProvider.overrideWithValue(MockConnectionMonitor(backend)),
  routingLogProvider.overrideWithValue(ThrottledRoutingLog(runs)),
  settingsRepositoryProvider.overrideWithValue(MockSettingsRepository(backend)),
  analyticsRepositoryProvider.overrideWithValue(
    MockAnalyticsRepository(backend, runs: runs),
  ),
  resourceRepositoryProvider.overrideWithValue(MockResourceRepository(backend)),
  safePlaceRepositoryProvider.overrideWithValue(
    MockSafePlaceRepository(backend),
  ),
  accountRepositoryProvider.overrideWithValue(MockAccountRepository(backend)),
  alertLogRepositoryProvider.overrideWithValue(MockAlertLogRepository(backend)),
  simulationRepositoryProvider.overrideWithValue(
    MockSimulationRepository(backend),
  ),
];

/// Overrides that run the dashboard on the Supabase project (see
/// docs/CONVENTIONS.md, "Supabase").
List<Override> supabaseOverrides(SupabaseBackend backend) => [
  authRepositoryProvider.overrideWithValue(backend.auth),
  staffSessionProvider.overrideWithValue(backend.auth),
  incidentRepositoryProvider.overrideWithValue(backend.incidents),
  unitRepositoryProvider.overrideWithValue(backend.units),
  crewRepositoryProvider.overrideWithValue(backend.crew),
  unitInventoryRepositoryProvider.overrideWithValue(backend.inventory),
  crowdReportRepositoryProvider.overrideWithValue(backend.crowdReports),
  residentRepositoryProvider.overrideWithValue(backend.residents),
  weatherRepositoryProvider.overrideWithValue(backend.weather),
  feedStatusRepositoryProvider.overrideWithValue(backend.feeds),
  forecastRepositoryProvider.overrideWithValue(backend.forecasts),
  reportRepositoryProvider.overrideWithValue(backend.reports),
  auditRepositoryProvider.overrideWithValue(backend.audit),
  connectionMonitorProvider.overrideWithValue(backend.connection),
  routingLogProvider.overrideWithValue(ThrottledRoutingLog(backend.routing)),
  settingsRepositoryProvider.overrideWithValue(backend.settings),
  analyticsRepositoryProvider.overrideWithValue(backend.analytics),
  resourceRepositoryProvider.overrideWithValue(backend.resources),
  safePlaceRepositoryProvider.overrideWithValue(backend.safePlaces),
  accountRepositoryProvider.overrideWithValue(backend.accounts),
  alertLogRepositoryProvider.overrideWithValue(backend.alertLog),
  simulationRepositoryProvider.overrideWithValue(backend.simulation),
];

// ---------------------------------------------------------------------------
// Live data.
// ---------------------------------------------------------------------------

final currentUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchUser(),
);

/// One event per session that ended without signing out (G2).
final sessionExpiredEventsProvider = StreamProvider<DateTime>(
  (ref) =>
      ref.watch(staffSessionProvider).watchExpired().map((_) => DateTime.now()),
);

/// True from a session expiry until the person signs in again or leaves
/// the Session expired page (G2).
class SessionExpiredController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool expired) => state = expired;
}

final sessionExpiredProvider = NotifierProvider<SessionExpiredController, bool>(
  SessionExpiredController.new,
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

/// Every unit's supplies as their crews last reported them (D7).
final unitSuppliesProvider = StreamProvider<List<UnitSupply>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(unitRepositoryProvider).watchSupplies()),
);

/// The crews (`unit_crew()`): every unit's for dispatchers and admins (D7
/// Units), only their own unit's for a responder (My unit).
final crewProvider = StreamProvider<List<CrewMember>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(unitRepositoryProvider).watchCrew()),
);

/// Crew requests: every one for admins, their unit's for a crew head or
/// assistant head, none for anyone else (2026-10-29).
final crewRequestsProvider = StreamProvider<List<CrewRequest>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(crewRepositoryProvider).watchRequests()),
);

/// Whom a crew head can ask to add: active responders not on their unit.
final crewCandidatesProvider = StreamProvider<List<CrewCandidate>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(crewRepositoryProvider).watchCandidates(),
  ),
);

/// The responder's own unit and its supplies (the "My unit" page).
final myUnitProvider = StreamProvider<ResponseUnit?>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(unitInventoryRepositoryProvider).watchMyUnit(),
  ),
);
final mySuppliesProvider = StreamProvider<List<UnitSupply>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(unitInventoryRepositoryProvider).watchMine(),
  ),
);

/// A supply is shown as low at or below this percent of full (A3).
final inventoryLowPercentProvider = Provider<double>((ref) {
  final settings = ref.watch(settingsProvider).value ?? const <AppSetting>[];
  for (final s in settings) {
    if (s.key == SettingKeys.inventoryLowPercent) return s.number.toDouble();
  }
  return UnitSupply.defaultLowPercent;
});

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

/// D10: the PAGASA feed's health; empty on sample data.
/// PHIVOLCS earthquakes near Manila from the last 48 hours (D10).
final earthquakesProvider = StreamProvider<List<Earthquake>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(feedStatusRepositoryProvider).watchEarthquakes(),
  ),
);

/// The newest water level of each river station (D10).
final riverLevelsProvider = StreamProvider<List<RiverLevel>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(feedStatusRepositoryProvider).watchRiverLevels(),
  ),
);

final feedStatusProvider = StreamProvider<List<FeedStatus>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(feedStatusRepositoryProvider).watchFeeds(),
  ),
);

/// A5: every NDRRMC report, newest first.
final reportsProvider = StreamProvider<List<NdrrmcReport>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(reportRepositoryProvider).watchReports(),
  ),
);

/// D8: the latest run of the 72-hour forecast; null when there is none.
final forecastProvider = StreamProvider<ForecastRun?>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(forecastRepositoryProvider).watchLatest(),
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

/// D4: the photos on an incident (2026-10-19).
final incidentPhotosProvider = StreamProvider.autoDispose
    .family<List<IncidentPhoto>, String>(
      (ref, id) => _forAccount(
        ref,
        () => ref.watch(incidentRepositoryProvider).watchPhotos(id),
      ),
    );

/// D4: what the resident who sent an SOS was told, and how it went out.
final incidentNoticesProvider =
    StreamProvider.family<List<ResidentNotice>, String>(
      (ref, id) => _forAccount(
        ref,
        () => ref.watch(incidentRepositoryProvider).watchNotices(id),
      ),
    );

/// The incident's post on the MDRRMD Facebook Page, if any.
final incidentFacebookPostProvider =
    StreamProvider.family<IncidentPost?, String>(
      (ref, id) => _forAccount(
        ref,
        () => ref.watch(incidentRepositoryProvider).watchFacebookPost(id),
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

/// A1: every staff account.
final staffAccountsProvider = StreamProvider<List<StaffAccount>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(accountRepositoryProvider).watchStaff()),
);

/// A1: every resident account (numbers masked).
final residentAccountsProvider = StreamProvider<List<Resident>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(accountRepositoryProvider).watchResidents(),
  ),
);

/// A2: every unit, retired ones included.
final allUnitsProvider = StreamProvider<List<ResponseUnit>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(resourceRepositoryProvider).watchUnits(),
  ),
);

/// Safe places (2026-10-19): the board's layer and the admin page. Hidden
/// ones are included (staff); the map leaves them out.
final safePlacesProvider = StreamProvider<List<SafePlace>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(safePlaceRepositoryProvider).watchPlaces(),
  ),
);

/// A2: responder accounts and their units.
final respondersProvider = StreamProvider<List<StaffAccount>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(resourceRepositoryProvider).watchResponders(),
  ),
);

/// A4's period: rolling windows ending now.
enum AnalyticsPeriod {
  day(Duration(days: 1)),
  week(Duration(days: 7)),
  month(Duration(days: 30));

  const AnalyticsPeriod(this.length);
  final Duration length;
}

class AnalyticsPeriodController extends Notifier<AnalyticsPeriod> {
  @override
  AnalyticsPeriod build() => AnalyticsPeriod.week;

  void select(AnalyticsPeriod p) => state = p;
}

final analyticsPeriodProvider =
    NotifierProvider<AnalyticsPeriodController, AnalyticsPeriod>(
      AnalyticsPeriodController.new,
    );

/// The incident history's period (Joshua, 2026-10-16).
enum HistoryPreset { today, week, month, custom }

@immutable
class HistoryRange {
  const HistoryRange(this.preset, this.from, this.to);

  final HistoryPreset preset;
  final DateTime from;
  final DateTime to;
}

class HistoryRangeController extends Notifier<HistoryRange> {
  @override
  HistoryRange build() => _range(HistoryPreset.week);

  HistoryRange _range(HistoryPreset preset) {
    final now = ref.read(historyNowProvider)();
    final from = switch (preset) {
      HistoryPreset.today => DateTime(now.year, now.month, now.day),
      HistoryPreset.month => now.subtract(const Duration(days: 30)),
      _ => now.subtract(const Duration(days: 7)),
    };
    // Open at the end, so incidents closed while the page is open appear.
    return HistoryRange(preset, from, now.add(const Duration(days: 1)));
  }

  void preset(HistoryPreset p) => state = _range(p);

  /// Whole days from [start] to [end], both included.
  void custom(DateTime start, DateTime end) => state = HistoryRange(
    HistoryPreset.custom,
    DateTime(start.year, start.month, start.day),
    DateTime(end.year, end.month, end.day).add(const Duration(days: 1)),
  );
}

final historyRangeProvider =
    NotifierProvider<HistoryRangeController, HistoryRange>(
      HistoryRangeController.new,
    );

/// The time the history counts back from (tests fix it).
final historyNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Closed incidents in the chosen period.
final historyProvider = StreamProvider.autoDispose<List<ClosedIncident>>((ref) {
  final range = ref.watch(historyRangeProvider);
  return _forAccount(
    ref,
    () => ref
        .watch(incidentRepositoryProvider)
        .watchHistory(from: range.from, to: range.to),
  );
});

/// The time A4 counts back from (tests fix it).
final analyticsNowProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// A4 for the chosen period; fetched when the page opens, the period
/// changes, or the admin refreshes.
final analyticsProvider = FutureProvider.autoDispose<AnalyticsReport>((ref) {
  final period = ref.watch(analyticsPeriodProvider);
  final now = ref.read(analyticsNowProvider)();
  return ref
      .watch(analyticsRepositoryProvider)
      .report(now.subtract(period.length), now.add(const Duration(minutes: 1)));
});

/// A3 settings (priority weights, the report limit, alert thresholds,
/// channels, numbers, simulation mode), live.
final settingsProvider = StreamProvider<List<AppSetting>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(settingsRepositoryProvider).watch()),
);

/// The alert thresholds an administrator set on A3; the built-in defaults
/// until they load.
final alertThresholdsProvider = Provider<AlertThresholds>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return settings == null
      ? const AlertThresholds()
      : AlertThresholds.fromSettings(settings);
});

/// D10: alerts with what happened to them on each channel, newest first.
final alertLogProvider = StreamProvider<List<SentAlert>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(alertLogRepositoryProvider).watchRecent(),
  ),
);

/// Which editors on A3 have changes that are not saved yet, so the router
/// can ask before leaving the page (plan 7.4 A3). A plain registry, not
/// provider state: editors update it from text listeners and on dispose.
class UnsavedChanges {
  final _dirty = <String>{};

  bool get any => _dirty.isNotEmpty;

  void set(String id, {required bool dirty}) =>
      dirty ? _dirty.add(id) : _dirty.remove(id);

  void clear() => _dirty.clear();
}

final unsavedChangesProvider = Provider<UnsavedChanges>(
  (ref) => UnsavedChanges(),
);

/// The Triage Queue rules with the weights an administrator set on A3; the
/// built-in defaults until they load.
final priorityRulesProvider = Provider<PriorityRules>((ref) {
  final settings = ref.watch(settingsProvider).value;
  return settings == null
      ? const PriorityRules()
      : PriorityRules.fromSettings(settings);
});

/// The bundled Manila road graph, loaded once on first use (plan 10.2).
final roadRouterProvider = FutureProvider<RoadRouter>(
  (ref) => loadManilaRouter(),
);

/// Ranks units by road travel time (Dijkstra over the bundled OSM road
/// graph, plan 10.2), falling back to straight-line estimates for units the
/// graph cannot place or when the graph fails to load. Each run is timed
/// for Chapter 4.
final unitSuggesterProvider = Provider<UnitSuggester>(
  (ref) => RoadNetworkSuggester(
    () => ref.read(roadRouterProvider.future),
    onRun: ref.read(routingLogProvider).log,
    hazards: () => ref.read(activeIncidentsProvider).value ?? const [],
    now: () => ref.read(clockProvider).value ?? DateTime.now(),
  ),
);

/// The chosen unit's road route to the incident, sent with the assignment
/// so the dispatch record and the responder's phone have it. Null when the
/// unit has no position, the road graph did not load, or either end is off
/// the map; the assignment goes ahead without it.
Future<RoadRoute?> routeForAssignment(
  WidgetRef ref,
  Incident incident,
  ResponseUnit unit,
) async {
  final from = unit.startingPoint(
    ref.read(clockProvider).value ?? DateTime.now(),
  );
  if (from == null) return null;
  try {
    final router = await ref.read(roadRouterProvider.future);
    final route = router.route(
      from,
      incident.currentLocation,
      penalty: HazardPenalty.fromIncidents(
        ref.read(activeIncidentsProvider).value ?? const [],
        except: incident.id,
      ),
    );
    if (route != null) {
      ref
          .read(routingLogProvider)
          .log(router.runFor(route, incidentId: incident.id));
    }
    return route;
  } on Object {
    return null;
  }
}

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

  void set(ThemeMode mode) => state = mode;
}

/// Whether an SOS nobody has been sent to yet pings on the map. Widget
/// tests turn it off: an animation that repeats never settles.
final sosPingProvider = Provider<bool>((ref) => true);

/// Whether a unit's marker moves along the streets between two reported
/// positions. Tests switch it off: a marker on its way keeps the frames
/// coming.
final unitGlideProvider = Provider<bool>((ref) => true);

/// Whether the pointer is over the side menu (it is open meanwhile).
class NavMenuHoverController extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool over) => state = over;
}

final navMenuHoveredProvider = NotifierProvider<NavMenuHoverController, bool>(
  NavMenuHoverController.new,
);

/// The side menu's widths, closed (icons only) and open (with names).
const navMenuClosedWidth = 64.0;
const navMenuOpenWidth = 248.0;
const navMenuSlide = Duration(milliseconds: 160);

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Whether a new SOS plays a sound (D11). On by default: a dispatcher
/// looking at another window must still hear it.
class SosSoundController extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool on) => state = on;
}

final sosSoundProvider = NotifierProvider<SosSoundController, bool>(
  SosSoundController.new,
);
