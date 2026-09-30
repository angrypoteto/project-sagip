import 'dart:async';

import 'package:flutter/foundation.dart';

import '../algorithms/dbscan.dart';
import '../algorithms/priority.dart';
import '../models/crowd_report.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/incident.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/road_route.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';
import 'live_value.dart';
import 'mock_seed.dart';

/// In-memory stand-in for the Supabase backend during Phase 1.
///
/// It enforces the same rules the database will (role checks, unit
/// availability, audit entries for every action) so the dashboard can be
/// built and tested before the real backend exists. [startSimulation] makes
/// it feel live: a new SOS arrives, a crowd-report cluster forms, and units
/// accept, drive, arrive, and finish on their own.
class MockBackend {
  MockBackend({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 350),
  }) : _clock = clock ?? DateTime.now {
    _seed = MockSeed(_clock());
    _staff = _seed.staff;
    _incidents = LiveValue({for (final i in _seed.incidents) i.id: i});
    _resolved = LiveValue(const []);
    _units = LiveValue({for (final u in _seed.units) u.id: u});
    _reports = LiveValue(_seed.crowdReports);
    _residents = LiveValue({for (final r in _seed.residents) r.id: r});
    _audit = LiveValue(_seed.audit);
    _weather = LiveValue(_seed.weather);
  }

  final DateTime Function() _clock;

  /// Artificial delay on every action, so loading states are visible.
  final Duration latency;

  late final MockSeed _seed;
  late final List<AppUser> _staff;
  late final LiveValue<Map<String, Incident>> _incidents;
  late final LiveValue<List<Incident>> _resolved;
  late final LiveValue<Map<String, ResponseUnit>> _units;
  late final LiveValue<List<CrowdReport>> _reports;
  late final LiveValue<Map<String, Resident>> _residents;
  late final LiveValue<List<AuditEntry>> _audit;
  late final LiveValue<WeatherStatus> _weather;
  final _user = LiveValue<AppUser?>(null);
  final _link = LiveValue<LinkState>(LinkState.live);

  // Simulation bookkeeping.
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _sosDelivered = false;
  bool _clusterReportAdded = false;
  int _nextIncidentNumber = 151;
  int _nextAuditNumber = 2000;
  final _assignedAt = <String, DateTime>{};
  final _routes = <String, RoadRoute>{};
  final _settings = LiveValue<Map<String, AppSetting>>({
    for (final s in defaultPrioritySettings) s.key: s,
  });

  Stream<List<AppSetting>> watchSettings() => _settings.watch().map(
    (m) => [...m.values]..sort((a, b) => a.key.compareTo(b.key)),
  );

  /// A3: admins only, checked like `set_setting`, and audited (FR11).
  Future<void> setSetting(String key, num value) async {
    final actor = await _authorize();
    if (!actor.isAdmin) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    final problem = checkSetting(_settings.value, key, value);
    if (problem != null) throw ActionRejected(problem);
    final old = _settings.value[key]!;
    if (old.value == value) return;
    _settings.value = {
      ..._settings.value,
      key: old.copyWith(
        value: value,
        updatedAt: _clock(),
        updatedBy: actor.displayName,
      ),
    };
    _log(
      actor,
      AuditAction.settingChanged,
      'app_setting',
      key,
      '${_plain(old.value)} → ${_plain(value)}',
    );
  }

  static String _plain(num v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();
  final _onSceneSince = <String, DateTime>{};

  /// The road route sent with the latest assignment of [incidentId], as the
  /// dispatch record keeps it on Supabase.
  RoadRoute? routeFor(String incidentId) => _routes[incidentId];
  final _smsCheckSentAt = <String, DateTime>{};

  /// When the simulated SOS arrives and when the third Dapitan St report
  /// completes a cluster.
  static const sosArrivesAfter = Duration(seconds: 20);
  static const clusterFormsAfter = Duration(seconds: 35);
  static const acceptAfter = Duration(seconds: 6);
  static const resolveAfterOnScene = Duration(seconds: 90);
  static const smsReplyAfter = Duration(seconds: 6);
  static const unitMetersPerSecond = 60.0;

  // ---------------------------------------------------------------- streams

  Stream<AppUser?> watchUser() => _user.watch();
  AppUser? get currentUser => _user.value;

  Stream<List<Incident>> watchActive() =>
      _incidents.watch().map((m) => m.values.toList(growable: false));

  Stream<List<Incident>> watchResolved(Duration since) =>
      _resolved.watch().map((all) {
        final cutoff = _clock().subtract(since);
        return [
          for (final i in all)
            if ((i.resolvedAt ?? i.receivedAt).isAfter(cutoff)) i,
        ];
      });

  Stream<List<ResponseUnit>> watchUnits() =>
      _units.watch().map((m) => m.values.toList(growable: false));

  Stream<List<CrowdReport>> watchReports(Duration window) =>
      _reports.watch().map((all) {
        final cutoff = _clock().subtract(window);
        return [
          for (final r in all)
            if (r.submittedAt.isAfter(cutoff)) r,
        ];
      });

  Stream<Resident?> watchResident(String id) =>
      _residents.watch().map((m) => m[id]);

  Stream<List<Resident>> watchVulnerable() => _residents.watch().map(
    (m) => [
      for (final r in m.values)
        if (r.isVulnerable) r,
    ],
  );

  Stream<List<AuditEntry>> watchAudit(int limit) => _audit.watch().map(
    (all) =>
        ([...all]..sort((a, b) {
              final byTime = b.at.compareTo(a.at);
              return byTime != 0 ? byTime : b.id.compareTo(a.id);
            }))
            .take(limit)
            .toList(growable: false),
  );

  Stream<WeatherStatus> watchWeather() => _weather.watch();

  Stream<LinkState> watchLink() => _link.watch();

  /// Scenario switcher: simulate losing and regaining the connection.
  void setLink(LinkState state) => _link.value = state;

  // -------------------------------------------------------------------- auth

  Future<AppUser> signIn(String email, String password) async {
    await _pause();
    if (_link.value == LinkState.offline) {
      throw const AuthException(AuthFailure.offline);
    }
    final match = _staff.where(
      (u) => u.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (match.isEmpty || password != MockSeed.demoPassword) {
      throw const AuthException(AuthFailure.wrongCredentials);
    }
    return _user.value = match.first;
  }

  Future<void> signOut() async {
    await _pause();
    _user.value = null;
  }

  // ---------------------------------------------------------------- actions

  Future<void> verify(String id, VerificationMethod method) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final now = _clock();
    _putIncident(
      incident
          .copyWith(
            verificationMethod: method,
            status: incident.status == IncidentStatus.pendingVerification
                ? IncidentStatus.confirmed
                : null,
          )
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.verified,
              at: now,
              actorName: actor.displayName,
              detail: method.name,
            ),
          ),
    );
    _log(actor, AuditAction.verified, 'incident_report', id, method.name);
  }

  Future<void> sendSmsCheck(String id) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final now = _clock();
    _smsCheckSentAt[id] = now;
    _putIncident(
      incident.withEvent(
        IncidentEvent(
          kind: IncidentEventKind.smsCheckSent,
          at: now,
          actorName: actor.displayName,
        ),
      ),
    );
    _log(actor, AuditAction.smsCheckSent, 'incident_report', id, null);
  }

  Future<void> markFalseReport(String id, {String? reason}) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final now = _clock();
    _releaseUnit(incident.assignedUnitId);
    _close(
      incident
          .copyWith(
            status: IncidentStatus.resolved,
            falseReport: true,
            resolvedAt: now,
          )
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.markedFalseReport,
              at: now,
              actorName: actor.displayName,
              detail: reason,
            ),
          ),
    );
    _log(actor, AuditAction.markedFalseReport, 'incident_report', id, reason);
  }

  Future<void> confirmType(String id, IncidentType type) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    _putIncident(
      incident
          .copyWith(confirmedType: type)
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.typeConfirmed,
              at: _clock(),
              actorName: actor.displayName,
              detail: type.name,
            ),
          ),
    );
    _log(actor, AuditAction.typeConfirmed, 'incident_report', id, type.name);
  }

  Future<void> assignUnit(
    String id,
    String unitId, {
    String? overrideReason,
    RoadRoute? route,
  }) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    final unit = _units.value[unitId];
    if (unit == null || !unit.isDispatchable) {
      throw const ActionRejected(ActionRejection.unitNotAvailable);
    }
    final now = _clock();
    final previous = incident.assignedUnitId;
    _releaseUnit(previous);
    _units.value = {
      ..._units.value,
      unitId: unit.copyWith(currentIncidentId: id),
    };
    _assignedAt[id] = now;
    if (route != null) _routes[id] = route;
    _putIncident(
      incident
          .copyWith(
            status: IncidentStatus.assigned,
            assignedUnitId: unitId,
            suggestionOverridden: overrideReason != null,
            overrideReason: overrideReason,
          )
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.assigned,
              at: now,
              actorName: actor.displayName,
              detail: unit.callSign,
            ),
          ),
    );
    _log(
      actor,
      previous == null ? AuditAction.unitAssigned : AuditAction.unitReassigned,
      'dispatch',
      id,
      overrideReason == null
          ? unit.callSign
          : '${unit.callSign} (override: $overrideReason)',
    );
  }

  Future<void> resolve(String id) async {
    final actor = await _authorize();
    final incident = _activeIncident(id);
    _resolveNow(incident, actor.displayName);
    _log(actor, AuditAction.resolved, 'incident_report', id, null);
  }

  Future<String> revealContact(String residentId) async {
    final actor = await _authorize();
    final resident = _residents.value[residentId];
    if (resident == null) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    _log(actor, AuditAction.contactViewed, 'manila_resident', residentId, null);
    return resident.contactNumber;
  }

  // ------------------------------------------------------------- simulation

  void startSimulation({Duration tick = const Duration(seconds: 1)}) {
    _timer ??= Timer.periodic(tick, (_) => runTick(tick));
  }

  void stopSimulation() {
    _timer?.cancel();
    _timer = null;
  }

  /// Advances the simulation by [step]. Public so tests can drive it.
  @visibleForTesting
  void runTick(Duration step) {
    if (_link.value != LinkState.live) return;
    _elapsed += step;
    final now = _clock();

    if (!_sosDelivered && _elapsed >= sosArrivesAfter) {
      _sosDelivered = true;
      _putIncident(_seed.arrivingSos(now));
    }
    if (!_clusterReportAdded && _elapsed >= clusterFormsAfter) {
      _clusterReportAdded = true;
      _reports.value = [..._reports.value, _seed.dapitanThirdReport(now)];
      recluster();
    }

    for (final incident in _incidents.value.values.toList()) {
      final unit = _units.value[incident.assignedUnitId];
      switch (incident.status) {
        case IncidentStatus.assigned when unit != null:
          final since = _assignedAt.putIfAbsent(incident.id, () => now);
          if (now.difference(since) >= acceptAfter) {
            _setUnit(unit.copyWith(status: UnitStatus.enRoute));
            _putIncident(
              incident
                  .copyWith(status: IncidentStatus.enRoute)
                  .withEvent(
                    IncidentEvent(
                      kind: IncidentEventKind.enRoute,
                      at: now,
                      actorName: unit.callSign,
                    ),
                  ),
            );
          }
        case IncidentStatus.enRoute when unit != null:
          _moveToward(unit, incident, step, now);
        case IncidentStatus.onScene:
          final since = _onSceneSince.putIfAbsent(incident.id, () => now);
          if (now.difference(since) >= resolveAfterOnScene) {
            _resolveNow(incident, unit?.callSign);
          }
        default:
          break;
      }

      final smsAt = _smsCheckSentAt[incident.id];
      final current = _incidents.value[incident.id];
      if (smsAt != null &&
          current != null &&
          now.difference(smsAt) >= smsReplyAfter) {
        _smsCheckSentAt.remove(incident.id);
        _putIncident(
          current.withEvent(
            IncidentEvent(
              kind: IncidentEventKind.smsReplyReceived,
              at: now,
              detail: 'YES',
            ),
          ),
        );
      }
    }

    if (_elapsed.inSeconds % 30 == 0) {
      final w = _weather.value;
      final drift = (_elapsed.inSeconds ~/ 30).isEven ? 1.5 : -1.0;
      _weather.value = WeatherStatus(
        signalLevel: w.signalLevel,
        rainfallMmPerHour: (w.rainfallMmPerHour + drift).clamp(5, 40),
        stormSurgeAdvisory: w.stormSurgeAdvisory,
        issuedAt: now,
        isSimulated: true,
      );
    }
  }

  /// Runs DBSCAN over the last 60 minutes of crowd reports and turns each
  /// cluster into a confirmed incident (the database trigger's job later).
  void recluster({Duration window = const Duration(minutes: 60)}) {
    final now = _clock();
    final recent = [
      for (final r in _reports.value)
        if (now.difference(r.submittedAt) <= window) r,
    ];
    final labels = dbscan(recent, locate: (r) => r.location);
    final clusters = <int, List<CrowdReport>>{};
    for (var i = 0; i < recent.length; i++) {
      if (labels[i] != kDbscanNoise) {
        (clusters[labels[i]] ??= []).add(recent[i]);
      }
    }

    var reports = {for (final r in _reports.value) r.id: r};
    for (final members in clusters.values) {
      final existingId = members
          .map((r) => r.incidentId)
          .firstWhere((id) => id != null, orElse: () => null);
      final ids = [for (final r in members) r.id];

      if (existingId != null && _incidents.value.containsKey(existingId)) {
        final incident = _incidents.value[existingId]!;
        _putIncident(
          incident.copyWith(
            crowdReportIds: {...incident.crowdReportIds, ...ids}.toList(),
          ),
        );
        for (final r in members) {
          reports[r.id] = r.copyWith(incidentId: existingId);
        }
      } else if (existingId == null) {
        final id = 'INC-${(_nextIncidentNumber++).toString().padLeft(4, '0')}';
        _putIncident(_clusterIncident(id, members, now));
        for (final r in members) {
          reports[r.id] = r.copyWith(incidentId: id);
        }
      }
    }
    _reports.value = reports.values.toList(growable: false);
  }

  Incident _clusterIncident(
    String id,
    List<CrowdReport> members,
    DateTime now,
  ) {
    final votes = <IncidentType, int>{};
    for (final r in members) {
      if (r.suggestedType != null) {
        votes[r.suggestedType!] = (votes[r.suggestedType!] ?? 0) + 1;
      }
    }
    final type = votes.isEmpty
        ? null
        : (votes.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
              .first
              .key;
    final lat =
        members.map((r) => r.location.lat).reduce((a, b) => a + b) /
        members.length;
    final lng =
        members.map((r) => r.location.lng).reduce((a, b) => a + b) /
        members.length;
    final earliest = members
        .map((r) => r.submittedAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return Incident(
      id: id,
      origin: IncidentOrigin.crowdCluster,
      channel: members.first.channel,
      status: IncidentStatus.confirmed,
      suggestedType: type,
      location: GeoPoint(lat, lng),
      barangay: members.first.barangay,
      district: members.first.district,
      capturedAt: earliest,
      receivedAt: now,
      crowdReportIds: [for (final r in members) r.id],
      events: [IncidentEvent(kind: IncidentEventKind.received, at: now)],
    );
  }

  void _moveToward(
    ResponseUnit unit,
    Incident incident,
    Duration step,
    DateTime now,
  ) {
    final from = unit.location ?? incident.location;
    final remaining = from.distanceTo(incident.location);
    final travel = unitMetersPerSecond * step.inMilliseconds / 1000;
    if (remaining <= travel + 30) {
      _setUnit(
        unit.copyWith(
          status: UnitStatus.onScene,
          location: incident.location,
          lastLocationAt: now,
        ),
      );
      _onSceneSince[incident.id] = now;
      _putIncident(
        incident
            .copyWith(status: IncidentStatus.onScene)
            .withEvent(
              IncidentEvent(
                kind: IncidentEventKind.onScene,
                at: now,
                actorName: unit.callSign,
              ),
            ),
      );
    } else {
      _setUnit(
        unit.copyWith(
          location: from.lerpTo(incident.location, travel / remaining),
          lastLocationAt: now,
        ),
      );
    }
  }

  void dispose() {
    stopSimulation();
    for (final live in <LiveValue<Object?>>[
      _incidents,
      _resolved,
      _units,
      _reports,
      _residents,
      _audit,
      _weather,
      _user,
      _link,
      _settings,
    ]) {
      live.close();
    }
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _pause() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
  }

  /// Same checks the database will do with RLS: online, signed in, and
  /// allowed to dispatch.
  Future<AppUser> _authorize() async {
    await _pause();
    if (_link.value == LinkState.offline) {
      throw const ActionRejected(ActionRejection.offline);
    }
    final user = _user.value;
    if (user == null || !user.canDispatch) {
      throw const ActionRejected(ActionRejection.notAllowed);
    }
    return user;
  }

  Incident _activeIncident(String id) {
    final incident = _incidents.value[id];
    if (incident == null) {
      throw const ActionRejected(ActionRejection.incidentClosed);
    }
    return incident;
  }

  void _putIncident(Incident incident) {
    _incidents.value = {..._incidents.value, incident.id: incident};
  }

  void _setUnit(ResponseUnit unit) {
    _units.value = {..._units.value, unit.id: unit};
  }

  void _releaseUnit(String? unitId) {
    final unit = _units.value[unitId];
    if (unit == null) return;
    _setUnit(unit.copyWith(status: UnitStatus.available, clearIncident: true));
  }

  void _resolveNow(Incident incident, String? actorName) {
    final now = _clock();
    _releaseUnit(incident.assignedUnitId);
    _close(
      incident
          .copyWith(status: IncidentStatus.resolved, resolvedAt: now)
          .withEvent(
            IncidentEvent(
              kind: IncidentEventKind.resolved,
              at: now,
              actorName: actorName,
            ),
          ),
    );
  }

  void _close(Incident incident) {
    _incidents.value = {..._incidents.value}..remove(incident.id);
    _resolved.value = [..._resolved.value, incident];
    _assignedAt.remove(incident.id);
    _onSceneSince.remove(incident.id);
    _smsCheckSentAt.remove(incident.id);
  }

  void _log(
    AppUser actor,
    AuditAction action,
    String table,
    String targetId,
    String? detail,
  ) {
    _audit.value = [
      ..._audit.value,
      AuditEntry(
        id: 'log-${_nextAuditNumber++}',
        at: _clock(),
        actorId: actor.id,
        actorName: actor.displayName,
        actorRole: actor.role,
        action: action,
        targetTable: table,
        targetId: targetId,
        detail: detail,
      ),
    ];
  }
}
