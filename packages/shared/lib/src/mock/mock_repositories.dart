import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/incident.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../repositories/repositories.dart';
import 'mock_backend.dart';

// Thin adapters from the repository interfaces to [MockBackend]. The Supabase
// versions in Phase 3 implement the same interfaces.

class MockAuthRepository implements AuthRepository {
  const MockAuthRepository(this._backend);

  final MockBackend _backend;

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
