import '../models/offline.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';
import 'mock_mobile_backend.dart';

// Thin adapters from the repository interfaces to [MockMobileBackend], the
// mobile app's Phase 1 backend.

class MockMobileAuthRepository implements AuthRepository {
  const MockMobileAuthRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<AppUser?> watchUser() => _backend.watchUser();

  @override
  AppUser? get currentUser => _backend.currentUser;

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      _backend.signIn(email, password);

  @override
  Future<void> signOut() => _backend.signOut();
}

class MockSosRepository implements SosRepository {
  const MockSosRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<List<SosRequest>> watchMine() => _backend.watchSos();

  @override
  Future<SosRequest> send({LocationFix? fix}) => _backend.sendSos(fix: fix);

  @override
  Future<void> addDetails(String clientId, SosDetails details) =>
      _backend.addDetails(clientId, details);
}

class MockOfflineQueue implements OfflineQueue {
  const MockOfflineQueue(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<List<QueuedRecord>> watchPending() => _backend.watchPending();

  @override
  Stream<QueuedRecord> deliveries() => _backend.deliveries();

  @override
  Future<void> retryNow() => _backend.retryNow();

  @override
  Future<void> remove(String id) => _backend.remove(id);
}

class MockSignalMonitor implements SignalMonitor {
  const MockSignalMonitor(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<SignalState> watch() => _backend.watchSignal();
}

class MockLocationService implements LocationService {
  const MockLocationService(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<LocationStatus> watch() => _backend.watchLocation();

  /// There are no settings to open in the mock; GPS just comes back on.
  @override
  Future<void> openSettings() async => _backend.setGps(on: true);
}

/// Residents only ever see their own profile on the phone.
class MockMobileResidentRepository implements ResidentRepository {
  const MockMobileResidentRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<Resident?> watchResident(String residentId) =>
      _backend.watchResident(residentId);

  @override
  Stream<List<Resident>> watchVulnerable() => const Stream.empty();

  @override
  Future<String> revealContact(String residentId) =>
      Future.error(const ActionRejected(ActionRejection.notAllowed));
}

class MockMobileWeatherRepository implements WeatherRepository {
  const MockMobileWeatherRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<WeatherStatus> watchCurrent() => _backend.watchWeather();
}
