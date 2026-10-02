import '../models/account.dart';
import '../models/alerts.dart';
import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/hazard_report.dart';
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

class MockHazardReportRepository implements HazardReportRepository {
  const MockHazardReportRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<List<HazardReport>> watchMine() => _backend.watchReports();

  @override
  Future<HazardReport> submit({
    required String description,
    IncidentType? type,
    LocationFix? fix,
  }) => _backend.submitReport(description: description, type: type, fix: fix);
}

class MockWebReportRepository implements WebReportRepository {
  const MockWebReportRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<List<HazardReport>> watchMine() => _backend.watchReports();

  @override
  Stream<ReportQuota> watchQuota() => _backend.watchReportQuota();

  @override
  Future<HazardReport> submit({
    required String clientId,
    required DateTime capturedAt,
    required String description,
    required GeoPoint location,
    IncidentType? type,
    double? accuracyMeters,
    Barangay? barangay,
  }) => _backend.submitWebReport(
    clientId: clientId,
    capturedAt: capturedAt,
    description: description,
    location: location,
    type: type,
    accuracyMeters: accuracyMeters,
    barangay: barangay,
  );
}

class MockResponderRepository implements ResponderRepository {
  const MockResponderRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<ResponderState> watch() => _backend.watchResponder();

  @override
  Future<void> accept(String incidentId) =>
      _backend.acceptAssignment(incidentId);

  @override
  Future<void> setStatus(UnitStatus status) => _backend.setUnitStatus(status);

  @override
  Future<void> arrive() => _backend.arrive();

  @override
  Future<void> confirmOnScene({
    required bool realEmergency,
    String? reason,
    int? peopleFound,
  }) => _backend.confirmOnScene(
    realEmergency: realEmergency,
    reason: reason,
    peopleFound: peopleFound,
  );

  @override
  Future<void> complete({
    required RescueOutcome outcome,
    required int personsAssisted,
    int housesDamaged = 0,
    int injured = 0,
    int missing = 0,
    int affectedFamilies = 0,
    String? notes,
  }) => _backend.complete(
    outcome: outcome,
    personsAssisted: personsAssisted,
    housesDamaged: housesDamaged,
    injured: injured,
    missing: missing,
    affectedFamilies: affectedFamilies,
    notes: notes,
  );

  @override
  Stream<List<CompletedAssignment>> watchHistory() => _backend.watchHistory();
}

class MockVulnerabilityRepository implements VulnerabilityRepository {
  const MockVulnerabilityRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Future<void> giveConsent() => _backend.giveConsent();

  @override
  Future<void> withdrawConsent() => _backend.withdrawConsent();

  @override
  Future<void> saveMember(VulnerableMember member) =>
      _backend.saveMember(member);

  @override
  Future<void> removeMember(String memberId) => _backend.removeMember(memberId);
}

class MockAlertRepository implements AlertRepository {
  const MockAlertRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<AlertFeed> watch() => _backend.watchAlerts();

  @override
  Future<void> refresh() => _backend.refreshAlerts();

  @override
  Future<void> markRead(String alertId) => _backend.markAlertRead(alertId);
}

class MockResidentAccountRepository implements ResidentAccountRepository {
  const MockResidentAccountRepository(this._backend);

  final MockMobileBackend _backend;

  @override
  Future<void> sendCode(String phone) => _backend.sendCode(phone);

  @override
  Future<AppUser> verifyCode({required String phone, required String code}) =>
      _backend.verifyCode(phone, code);

  @override
  Future<void> register({
    required String fullName,
    required String phone,
    required Barangay barangay,
  }) => _backend.register(fullName: fullName, phone: phone, barangay: barangay);

  @override
  Future<void> requestDataDeletion() => _backend.requestDataDeletion();
}

class MockPermissionService implements PermissionService {
  const MockPermissionService(this._backend);

  final MockMobileBackend _backend;

  @override
  Stream<Map<AppPermission, PermissionState>> watch() =>
      _backend.watchPermissions();

  @override
  Future<PermissionState> request(AppPermission permission) =>
      _backend.requestPermission(permission);

  /// There are no settings to open in the mock.
  @override
  Future<void> openSettings() async {}
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
