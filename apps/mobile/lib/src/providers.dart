import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:sagip_shared/sagip_shared.dart';

// ---------------------------------------------------------------------------
// Repositories. Each throws until main.dart overrides it, so screens only
// reach data through these interfaces (CLAUDE.md architecture rule).
// ---------------------------------------------------------------------------

Never _missing(String name) => throw UnimplementedError(
  '$name is not configured. Override it in main.dart.',
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => _missing('AuthRepository'),
);
final residentAccountRepositoryProvider = Provider<ResidentAccountRepository>(
  (ref) => _missing('ResidentAccountRepository'),
);
final permissionServiceProvider = Provider<PermissionService>(
  (ref) => _missing('PermissionService'),
);
final sosRepositoryProvider = Provider<SosRepository>(
  (ref) => _missing('SosRepository'),
);
final hazardReportRepositoryProvider = Provider<HazardReportRepository>(
  (ref) => _missing('HazardReportRepository'),
);
final responderRepositoryProvider = Provider<ResponderRepository>(
  (ref) => _missing('ResponderRepository'),
);
final offlineQueueProvider = Provider<OfflineQueue>(
  (ref) => _missing('OfflineQueue'),
);
final signalMonitorProvider = Provider<SignalMonitor>(
  (ref) => _missing('SignalMonitor'),
);
final locationServiceProvider = Provider<LocationService>(
  (ref) => _missing('LocationService'),
);
final residentRepositoryProvider = Provider<ResidentRepository>(
  (ref) => _missing('ResidentRepository'),
);
final weatherRepositoryProvider = Provider<WeatherRepository>(
  (ref) => _missing('WeatherRepository'),
);
final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => _missing('AlertRepository'),
);
final vulnerabilityRepositoryProvider = Provider<VulnerabilityRepository>(
  (ref) => _missing('VulnerabilityRepository'),
);

/// Only set when running on sample data: the Me screen shows demo tools
/// (signal and GPS switches) for it.
final mockBackendProvider = Provider<MockMobileBackend?>((ref) => null);

/// Whether map tiles load from the network. Tests turn this off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// The Dijkstra timing log for Chapter 4 (plan 10.2): in memory on sample
/// data, the `routing_run` table on Supabase. At most one run a minute per
/// job, since the phone re-routes on every GPS fix.
final routingLogProvider = Provider<RoutingLogRepository>(
  (ref) => ThrottledRoutingLog(MemoryRoutingLog()),
);

/// Storage on the phone (settings, and on the real backend the outbox and
/// saved copies). In memory unless main.dart provides Hive.
final localStoreProvider = Provider<LocalStore>((ref) => MemoryLocalStore());

/// What this build can really do while offline. The sample data simulates
/// every tier; the real app gets SMS, relay, and saved maps in Phase 5, and
/// screens must not promise them before then.
@immutable
class DeviceCapabilities {
  const DeviceCapabilities({
    required this.smsTier,
    required this.relayTier,
    required this.offlineMaps,
  });

  /// Tier 2: an SOS goes out by SMS without internet.
  final bool smsTier;

  /// Tier 3: an SOS is passed through nearby phones without any signal.
  final bool relayTier;

  /// The map around an accepted job is saved for offline use (FR13).
  final bool offlineMaps;

  static const simulated = DeviceCapabilities(
    smsTier: true,
    relayTier: true,
    offlineMaps: true,
  );

  /// The real app before Phase 5: the phone's queue only.
  static const queueOnly = DeviceCapabilities(
    smsTier: false,
    relayTier: false,
    offlineMaps: false,
  );
}

final capabilitiesProvider = Provider<DeviceCapabilities>(
  (ref) => DeviceCapabilities.simulated,
);

/// Overrides that run the app on [backend] (Phase 1).
List<Override> mockOverrides(
  MockMobileBackend backend, {
  bool demoTools = true,
}) => [
  mockBackendProvider.overrideWithValue(demoTools ? backend : null),
  authRepositoryProvider.overrideWithValue(MockMobileAuthRepository(backend)),
  residentAccountRepositoryProvider.overrideWithValue(
    MockResidentAccountRepository(backend),
  ),
  permissionServiceProvider.overrideWithValue(MockPermissionService(backend)),
  sosRepositoryProvider.overrideWithValue(MockSosRepository(backend)),
  hazardReportRepositoryProvider.overrideWithValue(
    MockHazardReportRepository(backend),
  ),
  offlineQueueProvider.overrideWithValue(MockOfflineQueue(backend)),
  responderRepositoryProvider.overrideWithValue(
    MockResponderRepository(backend),
  ),
  signalMonitorProvider.overrideWithValue(MockSignalMonitor(backend)),
  locationServiceProvider.overrideWithValue(MockLocationService(backend)),
  residentRepositoryProvider.overrideWithValue(
    MockMobileResidentRepository(backend),
  ),
  weatherRepositoryProvider.overrideWithValue(
    MockMobileWeatherRepository(backend),
  ),
  alertRepositoryProvider.overrideWithValue(MockAlertRepository(backend)),
  vulnerabilityRepositoryProvider.overrideWithValue(
    MockVulnerabilityRepository(backend),
  ),
];

/// Overrides that run the app on Supabase (part 6): records go through the
/// phone's outbox ([engine]); screens read the server's copy merged with
/// what is still on the phone, and saved copies when offline.
List<Override> liveOverrides({
  required SupabaseMobileBackend backend,
  required LocalStore store,
  required SyncEngine engine,
  required SignalMonitor signal,
  required LocationService location,
  required PermissionService permissions,
  Future<void> Function()? recheckSignal,
}) {
  String? account() => backend.accounts.currentUser?.id;
  return [
    localStoreProvider.overrideWithValue(store),
    capabilitiesProvider.overrideWithValue(DeviceCapabilities.queueOnly),
    authRepositoryProvider.overrideWithValue(backend.accounts),
    residentAccountRepositoryProvider.overrideWithValue(backend.accounts),
    permissionServiceProvider.overrideWithValue(permissions),
    sosRepositoryProvider.overrideWithValue(
      OutboxSosRepository(
        engine: engine,
        server: backend.remote,
        store: store,
        account: account,
      ),
    ),
    hazardReportRepositoryProvider.overrideWithValue(
      OutboxHazardReportRepository(
        engine: engine,
        server: backend.remote,
        store: store,
        account: account,
      ),
    ),
    responderRepositoryProvider.overrideWithValue(
      OutboxResponderRepository(
        engine: engine,
        server: backend.remote,
        store: store,
        account: account,
        location: location.watch(),
      ),
    ),
    offlineQueueProvider.overrideWithValue(
      OutboxOfflineQueue(engine, account, recheck: recheckSignal),
    ),
    signalMonitorProvider.overrideWithValue(signal),
    locationServiceProvider.overrideWithValue(location),
    residentRepositoryProvider.overrideWithValue(
      CachedResidentRepository(backend.residents, store),
    ),
    weatherRepositoryProvider.overrideWithValue(
      CachedWeatherRepository(backend.weather, store),
    ),
    alertRepositoryProvider.overrideWithValue(
      CachedAlertRepository(backend.alerts, store, account),
    ),
    vulnerabilityRepositoryProvider.overrideWithValue(backend.vulnerability),
    routingLogProvider.overrideWithValue(ThrottledRoutingLog(backend.routing)),
  ];
}

// ---------------------------------------------------------------------------
// Live data.
// ---------------------------------------------------------------------------

final currentUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchUser(),
);

/// Account data streams restart when the signed-in account changes, so one
/// account's data never stays in memory for the next. Signed out, they wait.
Stream<T> _forAccount<T>(Ref ref, Stream<T> Function() open) {
  final account = ref.watch(currentUserProvider.select((u) => u.value?.id));
  return account == null ? const Stream.empty() : open();
}

final permissionsProvider = StreamProvider<Map<AppPermission, PermissionState>>(
  (ref) => ref.watch(permissionServiceProvider).watch(),
);

/// Whether this phone has been through the welcome and permission steps
/// (S2). Saved on the phone.
class WelcomeSeen extends Notifier<bool> {
  static const _key = 'settings:welcome-seen';

  @override
  bool build() => ref.read(localStoreProvider).read(_key) == 'yes';

  void markSeen() {
    state = true;
    ref.read(localStoreProvider).write(_key, 'yes');
  }
}

final welcomeSeenProvider = NotifierProvider<WelcomeSeen, bool>(
  WelcomeSeen.new,
);

/// The Me screen's theme choice (S7). Follows the phone by default.
class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'settings:theme';

  @override
  ThemeMode build() {
    final saved = ref.read(localStoreProvider).read(_key);
    return ThemeMode.values.where((m) => m.name == saved).firstOrNull ??
        ThemeMode.system;
  }

  void set(ThemeMode mode) {
    state = mode;
    ref.read(localStoreProvider).write(_key, mode.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

final signalProvider = StreamProvider<SignalState>(
  (ref) => ref.watch(signalMonitorProvider).watch(),
);

final locationProvider = StreamProvider<LocationStatus>(
  (ref) => ref.watch(locationServiceProvider).watch(),
);

final mySosProvider = StreamProvider<List<SosRequest>>(
  (ref) => _forAccount(ref, () => ref.watch(sosRepositoryProvider).watchMine()),
);

final myReportsProvider = StreamProvider<List<HazardReport>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(hazardReportRepositoryProvider).watchMine(),
  ),
);

/// The responder's unit, assignment, and any new offer (F1 to F6).
final responderProvider = StreamProvider<ResponderState>(
  (ref) =>
      _forAccount(ref, () => ref.watch(responderRepositoryProvider).watch()),
);

/// The bundled Manila road graph (plan 10.2), loaded once on first use. The
/// phone routes on its own, so navigation works offline (FR13).
final roadRouterProvider = FutureProvider<RoadRouter>(
  (ref) => loadManilaRouter(),
);

/// The road route from [from] to a job, by Dijkstra on the phone. Recomputed
/// for every new position (a few milliseconds), so it follows the unit and
/// re-routes when it leaves the route. Null until the graph has loaded, or
/// when either end is off the map.
final navigationRouteProvider = Provider.autoDispose
    .family<RoadRoute?, ({GeoPoint from, GeoPoint to, String incidentId})>((
      ref,
      key,
    ) {
      final router = ref.watch(roadRouterProvider).value;
      if (router == null) return null;
      final route = router.route(key.from, key.to);
      if (route != null) {
        ref
            .read(routingLogProvider)
            .log(router.runFor(route, incidentId: key.incidentId));
      }
      return route;
    });

/// Distance, ETA, and direction from the unit to a job.
@immutable
class RouteEstimate {
  const RouteEstimate({
    required this.meters,
    required this.minutes,
    required this.bearing,
    required this.straightMeters,
    this.road,
  });

  /// Along the road route, or the straight line when there is none.
  final double meters;
  final int minutes;

  /// The direction to travel now, in degrees from north.
  final double bearing;

  /// Straight-line distance to the scene; "Arrived" uses this.
  final double straightMeters;

  /// The road route; null when estimated by straight line.
  final RoadRoute? road;
}

/// The unit's estimate for [a]: by road when the graph can route it, else by
/// straight-line distance (labelled as such on screen).
RouteEstimate? routeEstimate(WidgetRef ref, ResponderState? s, Assignment? a) {
  final from = s?.unit.location;
  if (from == null || a == null) return null;
  final straight = from.distanceTo(a.location);
  final road = ref.watch(
    navigationRouteProvider((
      from: from,
      to: a.location,
      incidentId: a.incidentId,
    )),
  );
  if (road != null) {
    return RouteEstimate(
      meters: road.meters,
      minutes: road.minutes.ceil().clamp(1, 999),
      bearing: road.initialBearing(),
      straightMeters: straight,
      road: road,
    );
  }
  return RouteEstimate(
    meters: straight,
    minutes: const StraightLineSuggester()
        .minutesFor(straight)
        .ceil()
        .clamp(1, 999),
    bearing: from.bearingTo(a.location),
    straightMeters: straight,
  );
}

/// Finished assignments, newest first (F7).
final responderHistoryProvider = StreamProvider<List<CompletedAssignment>>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(responderRepositoryProvider).watchHistory(),
  ),
);

/// Alerts for Manila and the forecast for the resident's barangay (R7).
final alertFeedProvider = StreamProvider<AlertFeed>(
  (ref) => _forAccount(ref, () => ref.watch(alertRepositoryProvider).watch()),
);

final pendingQueueProvider = StreamProvider<List<QueuedRecord>>(
  (ref) =>
      _forAccount(ref, () => ref.watch(offlineQueueProvider).watchPending()),
);

/// One event per record the server confirms (NFR1 delivery notice).
final deliveriesProvider = StreamProvider<QueuedRecord>(
  (ref) => ref.watch(offlineQueueProvider).deliveries(),
);

final weatherProvider = StreamProvider<WeatherStatus>(
  (ref) => _forAccount(
    ref,
    () => ref.watch(weatherRepositoryProvider).watchCurrent(),
  ),
);

/// The signed-in resident's profile (name, barangay).
final myProfileProvider = StreamProvider<Resident?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null || user.role != UserRole.resident) {
    return Stream.value(null);
  }
  return ref.watch(residentRepositoryProvider).watchResident(user.id);
});

/// The SOS that still needs attention, newest first; null if none.
final activeSosProvider = Provider<SosRequest?>((ref) {
  for (final s in ref.watch(mySosProvider).value ?? const <SosRequest>[]) {
    if (s.isActive) return s;
  }
  return null;
});

final sosByIdProvider = Provider.family<SosRequest?, String>((ref, id) {
  for (final s in ref.watch(mySosProvider).value ?? const <SosRequest>[]) {
    if (s.clientId == id) return s;
  }
  return null;
});

/// Ticks every second for elapsed timers.
final clockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now());
});
