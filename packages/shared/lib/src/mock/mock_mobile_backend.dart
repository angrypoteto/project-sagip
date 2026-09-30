import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/account.dart';
import '../models/assignment.dart';
import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/hazard_report.dart';
import '../models/offline.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/response_unit.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';
import 'live_value.dart';
import 'mock_seed.dart';

part 'mock_accounts.dart';
part 'mock_responder.dart';

/// How long each simulated step takes in [MockMobileBackend].
@immutable
class MockSosTiming {
  const MockSosTiming({
    this.send = const Duration(milliseconds: 900),
    this.sms = const Duration(seconds: 2),
    this.relay = const Duration(seconds: 3),
    this.verify = const Duration(seconds: 8),
    this.assign = const Duration(seconds: 6),
    this.depart = const Duration(seconds: 5),
    this.arrive = const Duration(seconds: 24),
    this.resolve = const Duration(seconds: 30),
    this.moveEvery = const Duration(seconds: 3),
    this.offerAfter = const Duration(seconds: 10),
    this.mapSave = const Duration(seconds: 4),
    this.drive = const Duration(seconds: 40),
  });

  /// Upload over the internet.
  final Duration send;

  /// Handing the SOS to the SMS app (Tier 2).
  final Duration sms;

  /// Finding a nearby phone to relay through (Tier 3).
  final Duration relay;

  // The simulated dispatcher and responder, counted from delivery.
  final Duration verify;
  final Duration assign;
  final Duration depart;
  final Duration arrive;
  final Duration resolve;

  /// How often the responder's position updates while en route (R3).
  /// Zero skips the in-between positions.
  final Duration moveEvery;

  /// Responder side (F1 to F6): when a new assignment is offered after
  /// sign-in, how long saving the offline map takes, and how long the drive
  /// to the scene takes.
  final Duration offerAfter;
  final Duration mapSave;
  final Duration drive;

  /// Everything happens on the next event-loop turn. For unit tests.
  static const instant = MockSosTiming(
    send: Duration.zero,
    sms: Duration.zero,
    relay: Duration.zero,
    verify: Duration.zero,
    assign: Duration.zero,
    depart: Duration.zero,
    arrive: Duration.zero,
    resolve: Duration.zero,
    moveEvery: Duration.zero,
    offerAfter: Duration.zero,
    mapSave: Duration.zero,
    drive: Duration.zero,
  );
}

/// In-memory stand-in for the phone's side of the backend in Phase 1: the
/// signed-in user, GPS, signal, the offline queue, and the resident's SOS
/// requests and hazard reports.
///
/// It follows the offline rules the real app must follow (CLAUDE.md): an
/// SOS is saved on the phone first, keeps its capture time, is sent in
/// capture order, and counts as delivered only when the "server" confirms
/// it. After delivery it plays the dispatcher: verify, assign R-03, drive
/// from the station toward the resident, on scene, resolved. Updates only
/// reach the phone while it has internet, as they would over Supabase
/// Realtime. Hazard reports go out over the internet only; SMS is for SOS.
///
/// Signed in as the responder, it offers R-03 an assignment, drives it to
/// the scene once accepted, and queues its status updates and completion
/// report like everything else (see `mock_responder.dart`).
class MockMobileBackend {
  MockMobileBackend({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 350),
    this.timing = const MockSosTiming(),
    this.simulateDispatch = true,
    this.autoOffers = true,
  }) : _clock = clock ?? DateTime.now {
    final seed = MockSeed(_clock());
    _residents = {for (final r in seed.residents) r.id: r};
    _weather = LiveValue(seed.weather);
    _location = LiveValue(
      LocationStatus(
        gpsOn: true,
        lastFix: LocationFix(
          point: const GeoPoint(14.6091, 120.9925),
          accuracyMeters: 8,
          at: _clock(),
          barangay: 'Barangay 412',
          district: 'Sampaloc',
        ),
      ),
    );
  }

  final DateTime Function() _clock;

  /// Artificial delay on sign-in, so loading states are visible.
  final Duration latency;
  final MockSosTiming timing;

  /// Whether a delivered SOS moves through verify, assign, and so on.
  final bool simulateDispatch;

  /// Whether the responder gets assignments on its own (tests offer them
  /// with [sendOfferNow]).
  final bool autoOffers;

  /// Demo accounts. Password: [MockSeed.demoPassword].
  static const resident = AppUser(
    id: 'res-001',
    displayName: 'Maria Dela Cruz',
    email: 'maria@sagip.test',
    role: UserRole.resident,
  );
  static const responder = AppUser(
    id: 'rsp-r03',
    displayName: 'J. Reyes',
    email: 'r03@sagip.test',
    role: UserRole.responder,
  );

  /// The sign-in code the mock accepts (S5).
  static const demoCode = '123456';

  /// Where R-03 waits before it is dispatched (Sampaloc station).
  static const stationR03 = GeoPoint(14.6045, 121.0010);

  /// Reports allowed per account per [reportWindow] (FR15, NFR7).
  /// Provisional until MDRRMD sets the limit.
  static const reportLimit = 5;
  static const reportWindow = Duration(hours: 1);

  late final Map<String, Resident> _residents;
  late final LiveValue<WeatherStatus> _weather;
  late final LiveValue<LocationStatus> _location;
  final _user = LiveValue<AppUser?>(null);
  final _signal = LiveValue<SignalState>(SignalState.internet);
  final _sos = LiveValue<List<SosRequest>>(const []);
  final _reports = LiveValue<List<HazardReport>>(const []);
  final _queue = LiveValue<List<QueuedRecord>>(const []);
  final _outbox = LiveValue<List<_Outgoing>>(const []);
  late final _responder = _ResponderSim(this);
  late final _accounts = _AccountsSim(this);
  final _deliveries = StreamController<QueuedRecord>.broadcast();

  final _timers = <Timer>[];
  final _deferred = <void Function()>[];

  /// Records that could not go out right away (for the delivery notice).
  final _waited = <String>{};
  var _pumping = false;
  var _pumpAgain = false;
  var _disposed = false;
  var _nextIncidentNumber = 160;
  var _nextReportNumber = 400;

  // ---------------------------------------------------------------- streams

  Stream<AppUser?> watchUser() => _user.watch();
  AppUser? get currentUser => _user.value;
  Stream<SignalState> watchSignal() => _signal.watch();
  Stream<LocationStatus> watchLocation() => _location.watch();
  Stream<WeatherStatus> watchWeather() => _weather.watch();

  Stream<List<SosRequest>> watchSos() => _sos.watch();

  Stream<List<HazardReport>> watchReports() => _reports.watch();

  /// Everything not yet confirmed by the server, oldest capture first.
  Stream<List<QueuedRecord>> watchPending() => _queue.watch();

  Stream<QueuedRecord> deliveries() => _deliveries.stream;

  Stream<ResponderState> watchResponder() => _responder.watch();

  /// Completion reports filed on this phone (for tests and history).
  List<CompletionReport> get completionReports => [
    for (final o in _outbox.value)
      if (o.completion != null) o.completion!,
  ];

  Stream<Resident?> watchResident(String id) =>
      _user.watch().map((_) => _residents[id]);

  // ------------------------------------------------------- scenario switcher

  SignalState get signal => _signal.value;

  /// Simulates moving between internet, SMS only, and no signal.
  void setSignal(SignalState next) {
    if (_signal.value == next) return;
    _signal.value = next;
    if (next == SignalState.internet) {
      final waiting = [..._deferred];
      _deferred.clear();
      for (final apply in waiting) {
        apply();
      }
    }
    unawaited(_pump());
  }

  /// Simulates turning GPS off (the last fix is kept) and on.
  void setGps({required bool on}) {
    _setGpsOnly(on);
    _responder.onGpsChanged();
  }

  void _setGpsOnly(bool on) {
    final current = _location.value;
    _location.value = LocationStatus(
      gpsOn: on,
      lastFix: current.lastFix == null
          ? null
          : LocationFix(
              point: current.lastFix!.point,
              accuracyMeters: current.lastFix!.accuracyMeters,
              at: on ? _clock() : current.lastFix!.at,
              barangay: current.lastFix!.barangay,
              district: current.lastFix!.district,
            ),
    );
  }

  // -------------------------------------------------------------------- auth

  Future<AppUser> signIn(String email, String password) async {
    await _pause();
    if (_signal.value != SignalState.internet) {
      throw const AuthException(AuthFailure.offline);
    }
    final match = [
      resident,
      responder,
    ].where((u) => u.email == email.trim().toLowerCase());
    if (match.isEmpty || password != MockSeed.demoPassword) {
      throw const AuthException(AuthFailure.wrongCredentials);
    }
    final user = _user.value = match.first;
    if (user.role == UserRole.responder) _responder.onSignIn();
    return user;
  }

  Future<void> signOut() async {
    await _pause();
    _responder.onSignOut();
    _user.value = null;
  }

  // --------------------------------------------------------------------- SOS

  /// Saves the SOS on the phone and starts sending it. Never waits for the
  /// network.
  Future<SosRequest> sendSos({LocationFix? fix}) async {
    final sos = SosRequest(
      clientId: newClientId(),
      capturedAt: _clock(),
      delivery: DeliveryState.savedOnPhone,
      location: fix?.point,
      accuracyMeters: fix?.accuracyMeters,
      barangay: fix?.barangay ?? _homeResident?.barangay,
      district: fix?.district ?? _homeResident?.district,
      mockLocationSuspected: fix?.mockProvider ?? false,
    );
    _setSos([sos, ..._sos.value]);
    unawaited(_pump());
    return sos;
  }

  Future<void> addDetails(String clientId, SosDetails details) async {
    final sos = _find(clientId);
    if (sos == null) return;
    _put(sos.copyWith(details: details));
  }

  Future<void> retryNow() => _pump();

  Future<void> remove(String id) async {
    _setSos([
      for (final s in _sos.value)
        if (!(s.clientId == id && s.delivery == DeliveryState.rejected)) s,
    ]);
    _setReports([
      for (final r in _reports.value)
        if (!(r.clientId == id && r.delivery == DeliveryState.rejected)) r,
    ]);
  }

  // ----------------------------------------------------------------- reports

  /// Checks a hazard report on the phone, saves it, and starts sending it.
  Future<HazardReport> submitReport({
    required String description,
    IncidentType? type,
    LocationFix? fix,
  }) async {
    final text = description.trim();
    if (text.isEmpty) {
      throw const ReportRejected(ReportRejection.emptyDescription);
    }
    if (fix == null) throw const ReportRejected(ReportRejection.noLocation);
    if (!roughlyInsideManila(fix.point)) {
      throw const ReportRejected(ReportRejection.outsideManila);
    }
    final since = _clock().subtract(reportWindow);
    final recent = _reports.value.where((r) => r.capturedAt.isAfter(since));
    if (recent.length >= reportLimit) {
      throw const ReportRejected(ReportRejection.rateLimited);
    }
    final report = HazardReport(
      clientId: newClientId(),
      capturedAt: _clock(),
      description: text,
      type: type,
      location: fix.point,
      accuracyMeters: fix.accuracyMeters,
      barangay: fix.barangay,
      district: fix.district,
      delivery: DeliveryState.savedOnPhone,
    );
    _setReports([report, ..._reports.value]);
    unawaited(_pump());
    return report;
  }

  // --------------------------------------------------------------- responder

  Future<void> acceptAssignment(String incidentId) =>
      _responder.accept(incidentId);
  Future<void> setUnitStatus(UnitStatus status) => _responder.setStatus(status);
  Future<void> arrive() => _responder.arrive();
  Future<void> confirmOnScene({
    required bool realEmergency,
    String? reason,
    int? peopleFound,
  }) => _responder.confirmOnScene(
    realEmergency: realEmergency,
    reason: reason,
    peopleFound: peopleFound,
  );
  Future<void> complete({
    required RescueOutcome outcome,
    required int personsAssisted,
    int housesDamaged = 0,
    int injured = 0,
    int missing = 0,
    int affectedFamilies = 0,
    String? notes,
  }) => _responder.complete(
    outcome: outcome,
    personsAssisted: personsAssisted,
    housesDamaged: housesDamaged,
    injured: injured,
    missing: missing,
    affectedFamilies: affectedFamilies,
    notes: notes,
  );

  // --------------------------------------------------- resident accounts

  Future<void> sendCode(String phone) => _accounts.sendCode(phone);
  Future<AppUser> verifyCode(String phone, String code) =>
      _accounts.verifyCode(phone, code);
  Future<void> register({
    required String fullName,
    required String phone,
    required Barangay barangay,
  }) =>
      _accounts.register(fullName: fullName, phone: phone, barangay: barangay);
  Future<void> requestDataDeletion() => _accounts.requestDataDeletion();

  /// Accounts that asked for their data to be deleted (for tests).
  List<String> get deletionRequests => _accounts.deletionRequests;

  Stream<Map<AppPermission, PermissionState>> watchPermissions() =>
      _accounts.permissions.watch();
  Future<PermissionState> requestPermission(AppPermission p) =>
      _accounts.request(p);

  /// Demo: the next permission request is refused with [state].
  void denyNextPermission(PermissionState state) => _accounts.denyNext = state;

  /// Demo tools: offer an assignment now, or have the dispatcher close it.
  void sendOfferNow() => _responder.sendOfferNow();
  void dispatcherCloses() => _responder.dispatcherCloses();

  void dispose() {
    _disposed = true;
    for (final t in _timers) {
      t.cancel();
    }
    _deliveries.close();
  }

  // ---------------------------------------------------------------- sending

  Resident? get _homeResident {
    final id = _user.value?.id;
    return id == null ? null : _residents[id];
  }

  SosRequest? _find(String id) {
    for (final s in _sos.value) {
      if (s.clientId == id) return s;
    }
    return null;
  }

  void _put(SosRequest next) {
    _setSos([
      for (final s in _sos.value) s.clientId == next.clientId ? next : s,
    ]);
  }

  HazardReport? _findReport(String id) {
    for (final r in _reports.value) {
      if (r.clientId == id) return r;
    }
    return null;
  }

  void _putReport(HazardReport next) {
    _setReports([
      for (final r in _reports.value) r.clientId == next.clientId ? next : r,
    ]);
  }

  void _setSos(List<SosRequest> next) {
    _sos.value = next;
    _refreshQueue();
  }

  void _setReports(List<HazardReport> next) {
    _reports.value = next;
    _refreshQueue();
  }

  void _addOutgoing(_Outgoing record) {
    _setOutbox([..._outbox.value, record]);
    unawaited(_pump());
  }

  void _setOutbox(List<_Outgoing> next) {
    _outbox.value = next;
    _refreshQueue();
  }

  void _refreshQueue() {
    _queue.value = [
      for (final s in _sos.value)
        if (s.delivery != DeliveryState.delivered)
          QueuedRecord(
            id: s.clientId,
            kind: QueuedKind.sos,
            capturedAt: s.capturedAt,
            delivery: s.delivery,
            rejectReason: s.rejectReason,
          ),
      for (final r in _reports.value)
        if (r.delivery != DeliveryState.delivered)
          QueuedRecord(
            id: r.clientId,
            kind: QueuedKind.crowdReport,
            capturedAt: r.capturedAt,
            delivery: r.delivery,
            rejectReason: r.rejectReason,
          ),
      for (final o in _outbox.value)
        if (o.delivery != DeliveryState.delivered)
          QueuedRecord(
            id: o.id,
            kind: o.kind,
            capturedAt: o.capturedAt,
            delivery: o.delivery,
          ),
    ]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
  }

  /// Works through pending records one at a time, oldest capture first, so
  /// they reach the server in the order they were made (NFR1).
  Future<void> _pump() async {
    if (_pumping) {
      _pumpAgain = true;
      return;
    }
    _pumping = true;
    try {
      do {
        _pumpAgain = false;
        final pending = [
          for (final r in _queue.value)
            if (r.delivery.isPending) r,
        ];
        for (final r in pending) {
          if (_disposed) return;
          switch (r.kind) {
            case QueuedKind.sos:
              await _advance(r.id);
            case QueuedKind.crowdReport:
              await _advanceReport(r.id);
            case QueuedKind.statusUpdate || QueuedKind.completionReport:
              await _advanceOutgoing(r.id);
          }
        }
      } while (_pumpAgain && !_disposed);
    } finally {
      _pumping = false;
    }
  }

  Future<void> _advance(String id) async {
    final sos = _find(id);
    if (sos == null || !sos.delivery.isPending) return;
    switch (_signal.value) {
      case SignalState.internet:
        final before = sos.delivery;
        _put(sos.copyWith(delivery: DeliveryState.sending));
        await _wait(timing.send);
        final now = _find(id);
        if (now == null) return;
        if (_signal.value != SignalState.internet) {
          // Lost the connection mid-upload: back to the tier it had reached.
          _waited.add(id);
          _put(now.copyWith(delivery: before));
          return;
        }
        _deliver(now);
      case SignalState.smsOnly:
        _waited.add(id);
        if (sos.delivery != DeliveryState.savedOnPhone &&
            sos.delivery != DeliveryState.relaying) {
          return;
        }
        await _wait(timing.sms);
        final now = _find(id);
        if (now == null || _signal.value != SignalState.smsOnly) return;
        _put(
          now.copyWith(
            delivery: DeliveryState.sentBySms,
            // SMS replaces a Bluetooth relay, which may never reach anyone.
            sentVia: ReportChannel.sms,
            sentAt: now.sentVia == ReportChannel.sms ? now.sentAt : _clock(),
          ),
        );
      case SignalState.noSignal:
        _waited.add(id);
        if (sos.delivery != DeliveryState.savedOnPhone) return;
        await _wait(timing.relay);
        final now = _find(id);
        if (now == null || _signal.value != SignalState.noSignal) return;
        _put(
          now.copyWith(
            delivery: DeliveryState.relaying,
            sentVia: now.sentVia ?? ReportChannel.bleRelay,
            sentAt: now.sentAt ?? _clock(),
          ),
        );
    }
  }

  /// Reports go out over the internet only; without it they wait.
  Future<void> _advanceReport(String id) async {
    final report = _findReport(id);
    if (report == null || !report.delivery.isPending) return;
    if (_signal.value != SignalState.internet) {
      _waited.add(id);
      return;
    }
    _putReport(report.copyWith(delivery: DeliveryState.sending));
    await _wait(timing.send);
    final now = _findReport(id);
    if (now == null) return;
    if (_signal.value != SignalState.internet) {
      _waited.add(id);
      _putReport(now.copyWith(delivery: DeliveryState.savedOnPhone));
      return;
    }
    _putReport(
      now.copyWith(
        delivery: DeliveryState.delivered,
        deliveredAt: _clock(),
        serverId: 'rep-${_nextReportNumber++}',
      ),
    );
    if (!_deliveries.isClosed) {
      _deliveries.add(
        QueuedRecord(
          id: id,
          kind: QueuedKind.crowdReport,
          capturedAt: now.capturedAt,
          delivery: DeliveryState.delivered,
          waitedOffline: _waited.remove(id),
        ),
      );
    }
  }

  _Outgoing? _findOutgoing(String id) {
    for (final o in _outbox.value) {
      if (o.id == id) return o;
    }
    return null;
  }

  void _putOutgoing(_Outgoing next) {
    _setOutbox([for (final o in _outbox.value) o.id == next.id ? next : o]);
  }

  /// Responder status updates and reports go over the internet only.
  Future<void> _advanceOutgoing(String id) async {
    final record = _findOutgoing(id);
    if (record == null || !record.delivery.isPending) return;
    if (_signal.value != SignalState.internet) {
      _waited.add(id);
      return;
    }
    _putOutgoing(record.withDelivery(DeliveryState.sending));
    await _wait(timing.send);
    final now = _findOutgoing(id);
    if (now == null) return;
    if (_signal.value != SignalState.internet) {
      _waited.add(id);
      _putOutgoing(now.withDelivery(DeliveryState.savedOnPhone));
      return;
    }
    _putOutgoing(now.withDelivery(DeliveryState.delivered));
    if (!_deliveries.isClosed) {
      _deliveries.add(
        QueuedRecord(
          id: id,
          kind: now.kind,
          capturedAt: now.capturedAt,
          delivery: DeliveryState.delivered,
          waitedOffline: _waited.remove(id),
        ),
      );
    }
  }

  void _deliver(SosRequest sos) {
    final now = _clock();
    final delivered = sos
        .copyWith(
          delivery: DeliveryState.delivered,
          sentVia: sos.sentVia ?? ReportChannel.app,
          sentAt: sos.sentAt ?? now,
          deliveredAt: now,
          incidentId: 'INC-0${_nextIncidentNumber++}',
        )
        .withStatus(IncidentStatus.pendingVerification, now);
    _put(delivered);
    if (!_deliveries.isClosed) {
      _deliveries.add(
        QueuedRecord(
          id: sos.clientId,
          kind: QueuedKind.sos,
          capturedAt: sos.capturedAt,
          delivery: DeliveryState.delivered,
          waitedOffline: _waited.remove(sos.clientId),
        ),
      );
    }
    if (simulateDispatch) _scheduleDispatch(sos.clientId);
  }

  /// Plays the dispatcher and the responder after delivery.
  void _scheduleDispatch(String id) {
    var at = Duration.zero;
    void step(Duration after, SosRequest Function(SosRequest s) change) {
      at += after;
      _timers.add(
        Timer(at, () {
          void apply() {
            final s = _find(id);
            if (s != null && s.status != IncidentStatus.resolved) {
              _put(change(s));
            }
          }

          // Updates arrive over realtime, so they wait for internet.
          if (_signal.value == SignalState.internet) {
            apply();
          } else {
            _deferred.add(apply);
          }
        }),
      );
    }

    step(
      timing.verify,
      (s) => s.withStatus(IncidentStatus.confirmed, _clock()),
    );
    step(
      timing.assign,
      (s) => s
          .withStatus(IncidentStatus.assigned, _clock())
          .copyWith(
            unitCallSign: 'R-03',
            unitType: UnitType.rescueBoat,
            etaMinutes: 9,
            responderLocation: stationR03,
            responderLocationAt: _clock(),
          ),
    );
    step(
      timing.depart,
      (s) => s
          .withStatus(IncidentStatus.enRoute, _clock())
          .copyWith(etaMinutes: 7, responderLocationAt: _clock()),
    );

    // Drive toward the resident in a straight line (Dijkstra road routes
    // come later), reporting a position every [MockSosTiming.moveEvery].
    const startEta = 7;
    final target = _find(id)?.location;
    final every = timing.moveEvery;
    final moves = target == null || every == Duration.zero
        ? 0
        : (timing.arrive.inMilliseconds ~/ every.inMilliseconds) - 1;
    for (var i = 1; i <= moves; i++) {
      final fraction = i / (moves + 1);
      step(
        every,
        (s) => s.copyWith(
          responderLocation: stationR03.lerpTo(target!, fraction),
          responderLocationAt: _clock(),
          etaMinutes: (startEta * (1 - fraction)).ceil().clamp(1, startEta),
        ),
      );
    }
    step(
      timing.arrive - every * (moves < 0 ? 0 : moves),
      (s) => s
          .withStatus(IncidentStatus.onScene, _clock())
          .copyWith(responderLocation: target, responderLocationAt: _clock()),
    );
    step(
      timing.resolve,
      (s) => s.withStatus(IncidentStatus.resolved, _clock()),
    );
  }

  Future<void> _wait(Duration d) => Future<void>.delayed(d);

  Future<void> _pause() =>
      latency == Duration.zero ? Future.value() : Future.delayed(latency);
}
