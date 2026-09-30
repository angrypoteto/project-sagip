import 'dart:async';

import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/hazard_report.dart';
import '../models/offline.dart';
import '../models/response_unit.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';
import 'mobile_server.dart';
import 'outbox.dart';
import 'streams.dart';
import 'sync_engine.dart';

// The phone's repositories on the real backend (part 6). Every SOS, report,
// and responder change is saved in the outbox first and sent by the
// [SyncEngine]; screens see the server's copy merged with what is still on
// the phone, so nothing disappears while offline (NFR1, FR13). The last
// server copy is kept on the phone for offline reading.

/// How long a delivered record still shapes what screens show, until the
/// server's copy catches up with it.
const _overlayFor = Duration(minutes: 2);

bool _stillShaping(OutboxEntry e, DateTime now) =>
    e.delivery.isPending ||
    (e.delivery == DeliveryState.delivered &&
        now.difference(e.deliveredAt ?? now) < _overlayFor);

// --------------------------------------------------------------------- SOS

class OutboxSosRepository implements SosRepository {
  OutboxSosRepository({
    required this._engine,
    required this._server,
    required this._store,
    required this._account,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncEngine _engine;
  final MobileServer _server;
  final LocalStore _store;
  final String? Function() _account;
  final DateTime Function() _clock;

  @override
  Stream<List<SosRequest>> watchMine() {
    final me = _account();
    if (me == null) return Stream.value(const []);
    final server = nullOnError(
      withSavedCopy(
        _store,
        'sos:$me',
        _server.watchMySos(),
        decode: (j) => decodeList(j, SosRequest.fromJson),
        encode: (l) => [for (final s in l) s.toJson()],
      ),
    );
    return combineLatest(
      [server, _engine.watch()],
      (v) =>
          mergeSos(v[0] as List<SosRequest>?, v[1]! as List<OutboxEntry>, me),
    );
  }

  /// The server's SOS requests with what is still on the phone on top.
  static List<SosRequest> mergeSos(
    List<SosRequest>? server,
    List<OutboxEntry> entries,
    String account,
  ) {
    final byId = {
      for (final s in server ?? const <SosRequest>[]) s.clientId: s,
    };
    final mine = [
      for (final e in entries)
        if (e.accountId == account) e,
    ];
    for (final e in mine) {
      if (e.action != OutboxAction.sos || byId.containsKey(e.id)) continue;
      final local = SosRequest.fromJson(e.payload);
      byId[e.id] = e.delivery == DeliveryState.delivered
          ? local
                .copyWith(
                  delivery: DeliveryState.delivered,
                  sentVia: ReportChannel.app,
                  sentAt: e.deliveredAt,
                  deliveredAt: e.deliveredAt,
                  incidentId: e.serverId,
                )
                .withStatus(
                  IncidentStatus.pendingVerification,
                  e.deliveredAt ?? e.capturedAt,
                )
          : local.copyWith(delivery: e.delivery, rejectReason: e.rejectReason);
    }
    // Details still on the phone show at once.
    for (final e in mine) {
      if (e.action != OutboxAction.sosDetails || !e.delivery.isPending) {
        continue;
      }
      final id = e.payload['client_id']! as String;
      final sos = byId[id];
      if (sos == null) continue;
      byId[id] = sos.copyWith(
        details: SosDetails.fromJson(
          (e.payload['details']! as Map).cast<String, Object?>(),
        ),
      );
    }
    return byId.values.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }

  @override
  Future<SosRequest> send({LocationFix? fix}) async {
    final me = _account();
    if (me == null) throw const ActionRejected(ActionRejection.notAllowed);
    final sos = SosRequest(
      clientId: newClientId(),
      capturedAt: _clock(),
      delivery: DeliveryState.savedOnPhone,
      location: fix?.point,
      accuracyMeters: fix == null || fix.manual ? null : fix.accuracyMeters,
      barangay: fix?.barangay,
      district: fix?.district,
      mockLocationSuspected: fix?.mockProvider ?? false,
    );
    await _engine.add(
      OutboxEntry(
        id: sos.clientId,
        action: OutboxAction.sos,
        accountId: me,
        capturedAt: sos.capturedAt,
        payload: sos.toJson(),
      ),
    );
    return sos;
  }

  @override
  Future<void> addDetails(String clientId, SosDetails details) async {
    final me = _account();
    if (me == null) return;
    await _engine.add(
      OutboxEntry(
        id: newClientId(),
        action: OutboxAction.sosDetails,
        accountId: me,
        capturedAt: _clock(),
        payload: {'client_id': clientId, 'details': details.toJson()},
      ),
    );
  }
}

// ----------------------------------------------------------------- reports

class OutboxHazardReportRepository implements HazardReportRepository {
  OutboxHazardReportRepository({
    required this._engine,
    required this._server,
    required this._store,
    required this._account,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncEngine _engine;
  final MobileServer _server;
  final LocalStore _store;
  final String? Function() _account;
  final DateTime Function() _clock;

  /// Reports allowed per account per hour (FR15, NFR7). Provisional; the
  /// server checks the same limit.
  static const limit = 5;

  @override
  Stream<List<HazardReport>> watchMine() {
    final me = _account();
    if (me == null) return Stream.value(const []);
    final server = nullOnError(
      withSavedCopy(
        _store,
        'reports:$me',
        _server.watchMyReports(),
        decode: (j) => decodeList(j, HazardReport.fromJson),
        encode: (l) => [for (final r in l) r.toJson()],
      ),
    );
    return combineLatest(
      [server, _engine.watch()],
      (v) => mergeReports(
        v[0] as List<HazardReport>?,
        v[1]! as List<OutboxEntry>,
        me,
      ),
    );
  }

  static List<HazardReport> mergeReports(
    List<HazardReport>? server,
    List<OutboxEntry> entries,
    String account,
  ) {
    final byId = {
      for (final r in server ?? const <HazardReport>[]) r.clientId: r,
    };
    for (final e in entries) {
      if (e.accountId != account ||
          e.action != OutboxAction.crowdReport ||
          byId.containsKey(e.id)) {
        continue;
      }
      final local = HazardReport.fromJson(e.payload);
      byId[e.id] = e.delivery == DeliveryState.delivered
          ? local.copyWith(
              delivery: DeliveryState.delivered,
              deliveredAt: e.deliveredAt,
              serverId: e.serverId,
              stage: ReportStage.checking,
            )
          : local.copyWith(delivery: e.delivery, rejectReason: e.rejectReason);
    }
    return byId.values.toList()
      ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  }

  @override
  Future<HazardReport> submit({
    required String description,
    IncidentType? type,
    LocationFix? fix,
  }) async {
    final me = _account();
    if (me == null) throw const ActionRejected(ActionRejection.notAllowed);
    final text = description.trim();
    if (text.isEmpty) {
      throw const ReportRejected(ReportRejection.emptyDescription);
    }
    if (fix == null) throw const ReportRejected(ReportRejection.noLocation);
    if (!roughlyInsideManila(fix.point)) {
      throw const ReportRejected(ReportRejection.outsideManila);
    }
    final now = _clock();
    final since = now.subtract(const Duration(hours: 1));
    final local = {
      for (final e in _engine.entries)
        if (e.accountId == me &&
            e.action == OutboxAction.crowdReport &&
            e.delivery != DeliveryState.rejected &&
            e.capturedAt.isAfter(since))
          e.id,
    };
    final saved = _store.read('reports:$me');
    var recent = local.length;
    if (saved is String) {
      for (final r in decodeList(
        jsonDecodeSafe(saved),
        HazardReport.fromJson,
      )) {
        if (!local.contains(r.clientId) && r.capturedAt.isAfter(since)) {
          recent++;
        }
      }
    }
    if (recent >= limit) {
      throw const ReportRejected(ReportRejection.rateLimited);
    }
    final report = HazardReport(
      clientId: newClientId(),
      capturedAt: now,
      description: text,
      type: type,
      location: fix.point,
      accuracyMeters: fix.manual ? null : fix.accuracyMeters,
      barangay: fix.barangay,
      district: fix.district,
      delivery: DeliveryState.savedOnPhone,
    );
    await _engine.add(
      OutboxEntry(
        id: report.clientId,
        action: OutboxAction.crowdReport,
        accountId: me,
        capturedAt: now,
        payload: report.toJson(),
      ),
    );
    return report;
  }
}

// --------------------------------------------------------------- responder

/// The responder's unit and jobs (F1 to F7). The last server copy of the
/// unit and its assignments is kept on the phone, so an accepted job can be
/// worked without a signal (FR13); status changes and the completion
/// report wait in the outbox and are applied on screen at once.
class OutboxResponderRepository implements ResponderRepository {
  OutboxResponderRepository({
    required this._engine,
    required this._server,
    required this._store,
    required this._account,
    this._location,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncEngine _engine;
  final MobileServer _server;
  final LocalStore _store;
  final String? Function() _account;
  final Stream<LocationStatus>? _location;
  final DateTime Function() _clock;

  /// The last state shown, for the checks in [setStatus].
  ResponderState? _latest;

  /// The job this phone was last working on, to notice when the dispatcher
  /// closes or reassigns it.
  Assignment? _lastCurrent;

  @override
  Stream<ResponderState> watch() {
    final me = _account();
    if (me == null) return const Stream.empty();
    final saved = _store.read('current:$me');
    if (saved is String) {
      final json = jsonDecodeSafe(saved);
      _lastCurrent = json is Map
          ? Assignment.fromJson(json.cast<String, Object?>())
          : null;
    }
    final unit = nullOnError(
      withSavedCopy(
        _store,
        'unit:$me',
        _server.watchUnit(),
        decode: (j) => j == null
            ? null
            : ResponseUnit.fromJson((j as Map).cast<String, Object?>()),
        encode: (u) => u?.toJson(),
      ),
    );
    final jobs = nullOnError(
      withSavedCopy(
        _store,
        'jobs:$me',
        _server.watchAssignments(),
        decode: (j) => decodeList(j, Assignment.fromJson),
        encode: (l) => [for (final a in l) a.toJson()],
      ),
    );
    final gps = _location ?? Stream<LocationStatus?>.value(null);
    return combineLatest([unit, jobs, _engine.watch(), gps], (v) {
      final state = _state(
        me,
        v[0] as ResponseUnit?,
        v[1] as List<Assignment>?,
        v[2]! as List<OutboxEntry>,
        v[3] as LocationStatus?,
      );
      if (state != null) _latest = state;
      return state;
    }).where((s) => s != null).cast<ResponderState>();
  }

  ResponderState? _state(
    String me,
    ResponseUnit? serverUnit,
    List<Assignment>? serverJobs,
    List<OutboxEntry> entries,
    LocationStatus? gps,
  ) {
    if (serverUnit == null) return null;
    var unit = serverUnit;
    var jobs = [...?serverJobs];
    final now = _clock();
    var cleared = false;
    final completed = <String>{};

    Assignment? find(String id) =>
        jobs.where((a) => a.incidentId == id).firstOrNull;
    void replace(Assignment a) =>
        jobs = [for (final x in jobs) x.incidentId == a.incidentId ? a : x];

    for (final e in entries) {
      if (e.accountId != me || !_stillShaping(e, now)) continue;
      final id = e.payload['incident_id'] as String?;
      switch (e.action) {
        case OutboxAction.accept:
          final a = id == null ? null : find(id);
          if (a != null && a.status == IncidentStatus.assigned) {
            replace(
              a.copyWith(
                status: IncidentStatus.enRoute,
                acceptedAt: e.capturedAt,
              ),
            );
          }
          if (id != null) {
            unit = unit.copyWith(
              status: UnitStatus.enRoute,
              currentIncidentId: id,
            );
          }
        case OutboxAction.arrive:
          final a = id == null ? null : find(id);
          if (a != null && a.status != IncidentStatus.onScene) {
            replace(
              a.copyWith(
                status: IncidentStatus.onScene,
                onSceneAt: e.capturedAt,
              ),
            );
          }
          unit = unit.copyWith(status: UnitStatus.onScene);
        case OutboxAction.confirmOnScene:
          final a = id == null ? null : find(id);
          if (a != null) {
            replace(
              a.copyWith(
                realEmergency: e.payload['real_emergency'] as bool?,
                notRealReason: e.payload['reason'] as String?,
                peopleFound: e.payload['people_found'] as int?,
              ),
            );
          }
        case OutboxAction.setStatus:
          final status = UnitStatus.values.byName(
            e.payload['status']! as String,
          );
          unit = unit.copyWith(status: status);
          if (status == UnitStatus.available) cleared = true;
        case OutboxAction.completion:
          final report = (e.payload['report']! as Map).cast<String, Object?>();
          final done = report['incident_id']! as String;
          completed.add(done);
          jobs = [
            for (final x in jobs)
              if (x.incidentId != done) x,
          ];
          unit = unit.copyWith(
            status: UnitStatus.available,
            clearIncident: true,
          );
        case OutboxAction.sos ||
            OutboxAction.sosDetails ||
            OutboxAction.crowdReport:
          break;
      }
    }

    var current = jobs
        .where(
          (a) =>
              a.status == IncidentStatus.enRoute ||
              a.status == IncidentStatus.onScene,
        )
        .firstOrNull;
    final offer = current == null
        ? jobs.where((a) => a.status == IncidentStatus.assigned).firstOrNull
        : null;

    final last = _lastCurrent;
    if (current != null) {
      _remember(me, current);
    } else if (last != null) {
      final gone =
          serverJobs != null &&
          !serverJobs.any((a) => a.incidentId == last.incidentId);
      if (completed.contains(last.incidentId) || cleared) {
        _remember(me, null);
      } else if (gone) {
        // The dispatcher closed or reassigned it (F3 banner).
        current = last.copyWith(closedByDispatcher: true);
      }
    }

    return ResponderState(
      unit: unit,
      current: current,
      offer: offer,
      locationSentAt: unit.lastLocationAt,
      gpsOn: gps?.gpsOn ?? true,
    );
  }

  void _remember(String me, Assignment? a) {
    if (a?.incidentId == _lastCurrent?.incidentId &&
        a?.status == _lastCurrent?.status) {
      return;
    }
    _lastCurrent = a;
    unawaited(
      _store.write(
        'current:$me',
        a == null ? null : jsonEncodeSafe(a.toJson()),
      ),
    );
  }

  Future<void> _queue(OutboxAction action, Map<String, Object?> payload) async {
    final me = _account();
    if (me == null) throw const ActionRejected(ActionRejection.notAllowed);
    await _engine.add(
      OutboxEntry(
        id: newClientId(),
        action: action,
        accountId: me,
        capturedAt: _clock(),
        payload: payload,
      ),
    );
  }

  @override
  Future<void> accept(String incidentId) =>
      _queue(OutboxAction.accept, {'incident_id': incidentId});

  @override
  Future<void> setStatus(UnitStatus status) async {
    final s = _latest;
    final current = s?.current;
    switch (status) {
      case UnitStatus.available:
        if (current != null && !current.closedByDispatcher) {
          throw const StatusRejected(StatusRejection.finishReportFirst);
        }
        await _queue(OutboxAction.setStatus, {'status': status.name});
      case UnitStatus.enRoute:
        if (current == null || current.closedByDispatcher) {
          final offer = s?.offer;
          if (offer == null) {
            throw const StatusRejected(StatusRejection.noAssignment);
          }
          await accept(offer.incidentId);
        } else if (current.status == IncidentStatus.onScene) {
          throw const StatusRejected(StatusRejection.alreadyOnScene);
        }
      case UnitStatus.onScene:
        if (current == null || current.closedByDispatcher) {
          throw const StatusRejected(StatusRejection.noAssignment);
        }
        await arrive();
    }
  }

  @override
  Future<void> arrive() async {
    final current = _latest?.current;
    if (current == null || current.status == IncidentStatus.onScene) return;
    await _queue(OutboxAction.arrive, {'incident_id': current.incidentId});
  }

  @override
  Future<void> confirmOnScene({
    required bool realEmergency,
    String? reason,
    int? peopleFound,
  }) async {
    final current = _latest?.current;
    if (current == null) return;
    await _queue(OutboxAction.confirmOnScene, {
      'incident_id': current.incidentId,
      'real_emergency': realEmergency,
      'reason': reason,
      'people_found': peopleFound,
    });
  }

  @override
  Future<void> complete({
    required RescueOutcome outcome,
    required int personsAssisted,
    int housesDamaged = 0,
    int injured = 0,
    int missing = 0,
    int affectedFamilies = 0,
    String? notes,
  }) async {
    final me = _account();
    final current = _latest?.current;
    if (me == null || current == null) return;
    final now = _clock();
    final report = CompletionReport(
      clientId: newClientId(),
      incidentId: current.incidentId,
      capturedAt: now,
      outcome: outcome,
      personsAssisted: personsAssisted,
      timeOnScene: now.difference(current.onSceneAt ?? now),
      housesDamaged: housesDamaged,
      injured: injured,
      missing: missing,
      affectedFamilies: affectedFamilies,
      notes: notes,
    );
    await _engine.add(
      OutboxEntry(
        id: report.clientId,
        action: OutboxAction.completion,
        accountId: me,
        capturedAt: now,
        payload: {
          'report': report.toJson(),
          // For History (F7) until the server's copy arrives.
          'type': current.type?.name,
          'barangay': current.barangay,
          'district': current.district,
        },
      ),
    );
  }

  @override
  Stream<List<CompletedAssignment>> watchHistory() {
    final me = _account();
    if (me == null) return Stream.value(const []);
    final server = nullOnError(
      withSavedCopy(
        _store,
        'history:$me',
        _server.watchHistory(),
        decode: (j) => decodeList(j, CompletedAssignment.fromJson),
        encode: (l) => [for (final c in l) c.toJson()],
      ),
    );
    return combineLatest(
      [server, _engine.watch()],
      (v) => mergeHistory(
        v[0] as List<CompletedAssignment>?,
        v[1]! as List<OutboxEntry>,
        me,
      ),
    );
  }

  static List<CompletedAssignment> mergeHistory(
    List<CompletedAssignment>? server,
    List<OutboxEntry> entries,
    String account,
  ) {
    final list = [...?server];
    final onServer = {for (final c in list) c.incidentId};
    for (final e in entries) {
      if (e.accountId != account || e.action != OutboxAction.completion) {
        continue;
      }
      final report = CompletionReport.fromJson(
        (e.payload['report']! as Map).cast<String, Object?>(),
      );
      if (onServer.contains(report.incidentId)) continue;
      list.add(
        CompletedAssignment(
          incidentId: report.incidentId,
          completedAt: report.capturedAt,
          type: enumFromJsonOrNull(IncidentType.values, e.payload['type']),
          barangay: e.payload['barangay'] as String? ?? '',
          district: e.payload['district'] as String? ?? '',
          outcome: report.outcome,
          personsAssisted: report.personsAssisted,
          reportDelivery: e.delivery,
        ),
      );
    }
    return list..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  }
}

// ------------------------------------------------------------ offline queue

/// The offline queue sheet (S6) over the outbox: this account's records
/// that the server has not confirmed yet, oldest first.
class OutboxOfflineQueue implements OfflineQueue {
  const OutboxOfflineQueue(this._engine, this._account);

  final SyncEngine _engine;
  final String? Function() _account;

  @override
  Stream<List<QueuedRecord>> watchPending() => _engine.watch().map(
    (all) => [
      for (final e in all)
        if (e.accountId == _account() && e.delivery != DeliveryState.delivered)
          e.toQueued(),
    ],
  );

  @override
  Stream<QueuedRecord> deliveries() => _engine.deliveries();

  @override
  Future<void> retryNow() => _engine.retryNow();

  @override
  Future<void> remove(String id) => _engine.remove(id);
}

// ------------------------------------------------------- position sharing

/// Shares the responder's position while signed in (FR9): at most every
/// [every], only while online, and never queued (only the newest position
/// matters). Positions older than the last one sent are skipped.
class ResponderLocationSharer {
  ResponderLocationSharer({
    required this._server,
    required this._location,
    required Stream<bool> online,
    this.every = const Duration(seconds: 15),
  }) : _onlineChanges = online;

  final MobileServer _server;
  final Stream<LocationStatus> _location;
  final Stream<bool> _onlineChanges;
  final Duration every;

  StreamSubscription<LocationStatus>? _fixes;
  StreamSubscription<bool>? _onlineSub;
  var _online = false;
  DateTime? _sentFixAt;
  var _busy = false;

  void start() {
    _onlineSub ??= _onlineChanges.listen((on) => _online = on);
    _fixes ??= _location.listen(_onFix);
  }

  Future<void> _onFix(LocationStatus status) async {
    final fix = status.lastFix;
    if (!_online || _busy || fix == null || !status.gpsOn) return;
    final last = _sentFixAt;
    if (last != null && fix.at.difference(last) < every) return;
    _busy = true;
    try {
      await _server.updateLocation(fix.point, fix.at);
      _sentFixAt = fix.at;
    } catch (_) {
      // Next fix tries again.
    } finally {
      _busy = false;
    }
  }

  Future<void> stop() async {
    await _fixes?.cancel();
    await _onlineSub?.cancel();
    _fixes = null;
    _onlineSub = null;
  }
}
