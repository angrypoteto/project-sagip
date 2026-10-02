import '../algorithms/routing_log.dart';
import '../models/alerts.dart';
import '../models/analytics.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';
import 'mock_backend.dart';

// Thin adapters from the repository interfaces to [MockBackend]. The Supabase
// versions in Phase 3 implement the same interfaces.

class MockAuthRepository implements AuthRepository, StaffSessionRepository {
  const MockAuthRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<AppUser?> watchUser() => _backend.watchUser();

  @override
  AppUser? get currentUser => _backend.currentUser;

  @override
  Stream<void> watchExpired() => _backend.watchExpired();

  @override
  Future<void> changePassword({
    required String current,
    required String next,
  }) => _backend.changePassword(current: current, next: next);

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      _backend.signIn(email, password);

  @override
  Future<void> signOut() => _backend.signOut();
}

class MockIncidentRepository implements IncidentRepository {
  const MockIncidentRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<Incident>> watchActive() => _backend.watchActive();

  @override
  Stream<List<Incident>> watchResolved({
    Duration since = const Duration(hours: 12),
  }) => _backend.watchResolved(since);

  @override
  Future<void> verify(String incidentId, VerificationMethod method) =>
      _backend.verify(incidentId, method);

  @override
  Future<void> sendSmsCheck(String incidentId) =>
      _backend.sendSmsCheck(incidentId);

  @override
  Future<void> markFalseReport(String incidentId, {String? reason}) =>
      _backend.markFalseReport(incidentId, reason: reason);

  @override
  Future<void> confirmType(String incidentId, IncidentType type) =>
      _backend.confirmType(incidentId, type);

  @override
  Future<void> assignUnit(
    String incidentId,
    String unitId, {
    String? overrideReason,
    RoadRoute? route,
  }) => _backend.assignUnit(
    incidentId,
    unitId,
    overrideReason: overrideReason,
    route: route,
  );

  @override
  Future<void> resolve(String incidentId) => _backend.resolve(incidentId);
}

class MockAccountRepository implements AccountRepository {
  const MockAccountRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<StaffAccount>> watchStaff() => _backend.watchStaff();

  @override
  Stream<List<Resident>> watchResidents() => _backend.watchAllResidents();

  @override
  Future<({String id, String temporaryPassword})> createStaff({
    required String email,
    required String displayName,
    required UserRole role,
    String? unitId,
  }) => _backend.createStaff(
    email: email,
    displayName: displayName,
    role: role,
    unitId: unitId,
  );

  @override
  Future<void> updateStaff(
    String id, {
    required String displayName,
    required UserRole role,
  }) => _backend.updateStaff(id, displayName: displayName, role: role);

  @override
  Future<void> setStaffActive(String id, {required bool active}) =>
      _backend.setStaffActive(id, active: active);

  @override
  Future<String> resetPassword(String id) => _backend.resetPassword(id);

  @override
  Future<void> setResidentSuspended(
    String residentId, {
    required bool suspended,
  }) => _backend.setResidentSuspended(residentId, suspended: suspended);
}

class MockResourceRepository implements ResourceRepository {
  const MockResourceRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<ResponseUnit>> watchUnits() => _backend.watchAllUnits();

  @override
  Stream<List<StaffAccount>> watchResponders() => _backend.watchResponders();

  @override
  Future<String> saveUnit({
    String? id,
    required String callSign,
    required UnitType type,
    required String station,
    required int crewSize,
  }) => _backend.saveUnit(
    id: id,
    callSign: callSign,
    type: type,
    station: station,
    crewSize: crewSize,
  );

  @override
  Future<void> retireUnit(String id) => _backend.retireUnit(id);

  @override
  Future<void> restoreUnit(String id) => _backend.restoreUnit(id);

  @override
  Future<void> setResponderUnit(String staffId, String? unitId) =>
      _backend.setResponderUnit(staffId, unitId);
}

class MockAnalyticsRepository implements AnalyticsRepository {
  const MockAnalyticsRepository(this._backend, {this.runs});

  final MockBackend _backend;

  /// The dashboard's timing log on sample data, for the Dijkstra figures.
  final MemoryRoutingLog? runs;

  @override
  Future<AnalyticsReport> report(DateTime from, DateTime to) =>
      _backend.analytics(from, to, runs: runs?.runs ?? const []);
}

class MockSettingsRepository implements SettingsRepository {
  const MockSettingsRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<AppSetting>> watch() => _backend.watchSettings();

  @override
  Future<void> set(String key, Object value) => _backend.setSetting(key, value);
}

class MockAlertLogRepository implements AlertLogRepository {
  const MockAlertLogRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<SentAlert>> watchRecent({int limit = 30}) =>
      _backend.watchAlertLog(limit);
}

class MockSimulationRepository implements SimulationRepository {
  const MockSimulationRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<void> simulateWeather({
    required int signal,
    required double rainfallMmPerHour,
    double? surgeMeters,
  }) => _backend.simulateWeather(
    signal: signal,
    rainfallMmPerHour: rainfallMmPerHour,
    surgeMeters: surgeMeters,
  );
}

/// The hotline and gateway number as set on the mock's A3.
class MockClientConfigRepository implements ClientConfigRepository {
  const MockClientConfigRepository(this._backend);

  final MockBackend _backend;

  @override
  Future<ClientConfig> fetch() async => _backend.clientConfig;
}

class MockUnitRepository implements UnitRepository {
  const MockUnitRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<ResponseUnit>> watchAll() => _backend.watchUnits();
}

class MockCrowdReportRepository implements CrowdReportRepository {
  const MockCrowdReportRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<CrowdReport>> watchRecent({
    Duration window = const Duration(minutes: 60),
  }) => _backend.watchReports(window);
}

class MockResidentRepository implements ResidentRepository {
  const MockResidentRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<Resident?> watchResident(String residentId) =>
      _backend.watchResident(residentId);

  @override
  Stream<List<Resident>> watchVulnerable() => _backend.watchVulnerable();

  @override
  Future<String> revealContact(String residentId) =>
      _backend.revealContact(residentId);
}

class MockWeatherRepository implements WeatherRepository {
  const MockWeatherRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<WeatherStatus> watchCurrent() => _backend.watchWeather();
}

class MockAuditRepository implements AuditRepository {
  const MockAuditRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<AuditEntry>> watchRecent({int limit = 200}) =>
      _backend.watchAudit(limit);
}

class MockConnectionMonitor implements ConnectionMonitor {
  const MockConnectionMonitor(this._backend);

  final MockBackend _backend;

  @override
  Stream<LinkState> watch() => _backend.watchLink();
}
