import 'dart:typed_data';

import '../algorithms/dijkstra/routing_log.dart';
import '../models/alerts.dart';
import '../models/analytics.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/facebook_post.dart';
import '../models/geo_point.dart';
import '../models/incident.dart';
import '../models/incident_history.dart';
import '../models/ndrrmc.dart';
import '../models/people.dart';
import '../models/photo.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/safe_place.dart';
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

  @override
  Future<void> confirmCancel(String incidentId) =>
      _backend.confirmCancel(incidentId);

  @override
  Stream<List<ResidentNotice>> watchNotices(String incidentId) =>
      _backend.watchNotices(incidentId);

  /// The sample data posts nothing on Facebook.
  /// Sample data has no photos.
  @override
  Stream<List<IncidentPhoto>> watchPhotos(String incidentId) =>
      Stream.value(const []);

  @override
  Stream<IncidentPost?> watchFacebookPost(String incidentId) =>
      Stream.value(null);

  ClosedIncident _withReport(Incident i) {
    final r = _backend.completionFor(i.id);
    return r == null
        ? ClosedIncident(incident: i)
        : ClosedIncident(
            incident: i,
            outcome: r.outcome,
            personsAssisted: r.personsAssisted,
            housesDamaged: r.housesDamaged,
            injured: r.injured,
            missing: r.missing,
            affectedFamilies: r.affectedFamilies,
          );
  }

  /// The sample's closed incidents, with the past rescues' reports.
  @override
  Stream<List<ClosedIncident>> watchHistory({
    required DateTime from,
    required DateTime to,
    int limit = 1000,
  }) => _backend
      .watchResolved(const Duration(days: 3650))
      .map(
        (all) => [
          for (final i
              in [...all]..sort(
                (a, b) => (b.resolvedAt ?? b.receivedAt).compareTo(
                  a.resolvedAt ?? a.receivedAt,
                ),
              ))
            if (!(i.resolvedAt ?? i.receivedAt).isBefore(from) &&
                !(i.resolvedAt ?? i.receivedAt).isAfter(to))
              _withReport(i),
        ].take(limit).toList(),
      );
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
  Future<void> setUnitHome(String id, GeoPoint? home) =>
      _backend.setUnitHome(id, home);

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

  @override
  Future<String> issue({
    required AlertSource source,
    required AlertLevel level,
    required String title,
    required String body,
    List<String> guidance = const [],
    List<String> barangays = const [],
  }) => _backend.issueAlert(
    source: source,
    level: level,
    title: title,
    body: body,
    guidance: guidance,
    barangays: barangays,
  );

  @override
  Future<void> end(String alertId) => _backend.endAlert(alertId);
}

/// Sample data has no PAGASA feed (its weather is simulated) until a test
/// sets one ([MockBackend.setFeeds]).
class MockFeedStatusRepository implements FeedStatusRepository {
  const MockFeedStatusRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<FeedStatus>> watchFeeds() => _backend.watchFeeds();

  @override
  Stream<List<Earthquake>> watchEarthquakes() => _backend.watchEarthquakes();

  @override
  Stream<List<RiverLevel>> watchRiverLevels() => _backend.watchRiverLevels();
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

  @override
  Future<String> simulateSos({
    required String barangay,
    bool vulnerable = false,
  }) => _backend.simulateSos(barangay: barangay, vulnerable: vulnerable);

  @override
  Future<void> simulateCrowdReports({
    required String barangay,
    required IncidentType type,
    int count = 3,
  }) => _backend.simulateCrowdReports(
    barangay: barangay,
    type: type,
    count: count,
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

  @override
  Stream<List<UnitSupply>> watchSupplies() => _backend.watchSupplies();
}

class MockUnitInventoryRepository implements UnitInventoryRepository {
  const MockUnitInventoryRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<ResponseUnit?> watchMyUnit() => _backend.watchMyUnit();

  @override
  Stream<List<UnitSupply>> watchMine() => _backend.watchMySupplies();

  @override
  Future<void> setSupply(SupplyItem item, num quantity, {num? capacity}) =>
      _backend.setSupply(item, quantity, capacity: capacity);
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

class MockReportRepository implements ReportRepository {
  const MockReportRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<NdrrmcReport>> watchReports() => _backend.watchNdrrmcReports();

  @override
  Future<ReportSource> source(DateTime from, DateTime to) =>
      _backend.reportSource(from, to);

  @override
  Future<String> save({
    String? id,
    required DateTime from,
    required DateTime to,
    required String title,
    required List<ReportSection> sections,
    int? generationMs,
    ReportMethod? method,
  }) => _backend.saveNdrrmcReport(
    id: id,
    from: from,
    to: to,
    title: title,
    sections: sections,
    generationMs: generationMs,
    method: method,
  );

  @override
  Future<ReportRewrite> rewrite({
    required ReportSource source,
    required List<ReportSection> sections,
  }) => _backend.rewriteReport(source, sections);

  @override
  Future<void> finalize(String id) => _backend.finalizeNdrrmcReport(id);

  @override
  Future<void> storePdf(String id, Uint8List bytes) =>
      _backend.storeReportPdf(id, bytes);

  @override
  Future<Uint8List> storedPdf(String id) => _backend.storedReportPdf(id);
}

class MockForecastRepository implements ForecastRepository {
  const MockForecastRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<ForecastRun?> watchLatest() => _backend.watchForecast();
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

class MockSafePlaceRepository implements SafePlaceRepository {
  const MockSafePlaceRepository(this._backend);

  final MockBackend _backend;

  @override
  Stream<List<SafePlace>> watchPlaces() => _backend.watchSafePlaces();

  @override
  Future<List<SafePlaceOption>> nearest(
    GeoPoint from,
    IncidentType need, {
    int limit = SafePlaceRules.defaultLimit,
  }) async => _backend.safePlacesNear(from, need, limit: limit);

  @override
  Future<String> savePlace({
    String? id,
    String? name,
    required SafePlaceKind kind,
    required GeoPoint location,
    required bool official,
  }) => _backend.saveSafePlace(
    id: id,
    name: name,
    kind: kind,
    location: location,
    official: official,
  );

  @override
  Future<void> setHidden(String id, bool hidden) =>
      _backend.setSafePlaceHidden(id, hidden);
}
