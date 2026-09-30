import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
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

/// Only set when running on sample data: the Me screen shows demo tools
/// (signal and GPS switches) for it.
final mockBackendProvider = Provider<MockMobileBackend?>((ref) => null);

/// Whether map tiles load from the network. Tests turn this off.
final mapTilesEnabledProvider = Provider<bool>((ref) => true);

/// Overrides that run the app on [backend] (Phase 1).
List<Override> mockOverrides(
  MockMobileBackend backend, {
  bool demoTools = true,
}) => [
  mockBackendProvider.overrideWithValue(demoTools ? backend : null),
  authRepositoryProvider.overrideWithValue(MockMobileAuthRepository(backend)),
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
];

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

/// Straight-line distance and ETA from the unit to its assignment. Road
/// routes replace this with Dijkstra in Phase 4.
({double meters, int minutes, double bearing})? routeEstimate(
  ResponderState? s,
  Assignment? a,
) {
  final from = s?.unit.location;
  if (from == null || a == null) return null;
  final meters = from.distanceTo(a.location);
  return (
    meters: meters,
    minutes: const StraightLineSuggester()
        .minutesFor(meters)
        .ceil()
        .clamp(1, 999),
    bearing: from.bearingTo(a.location),
  );
}

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
