import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/enums.dart';
import '../models/geo_point.dart';
import '../models/offline.dart';
import '../models/people.dart';
import '../models/records.dart';
import '../models/sos.dart';
import '../repositories/repositories.dart';
import 'live_value.dart';
import 'mock_seed.dart';

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
  );
}

/// In-memory stand-in for the phone's side of the backend in Phase 1: the
/// signed-in user, GPS, signal, the offline queue, and the resident's SOS
/// requests.
///
/// It follows the offline rules the real app must follow (CLAUDE.md): an
/// SOS is saved on the phone first, keeps its capture time, is sent in
/// capture order, and counts as delivered only when the "server" confirms
/// it. After delivery it plays the dispatcher: verify, assign R-03, en
/// route, on scene, resolved. Updates only reach the phone while it has
/// internet, as they would over Supabase Realtime.
class MockMobileBackend {
  MockMobileBackend({
    DateTime Function()? clock,
    this.latency = const Duration(milliseconds: 350),
    this.timing = const MockSosTiming(),
    this.simulateDispatch = true,
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

  late final Map<String, Resident> _residents;
  late final LiveValue<WeatherStatus> _weather;
  late final LiveValue<LocationStatus> _location;
  final _user = LiveValue<AppUser?>(null);
  final _signal = LiveValue<SignalState>(SignalState.internet);
  final _sos = LiveValue<List<SosRequest>>(const []);
  final _deliveries = StreamController<QueuedRecord>.broadcast();

  final _timers = <Timer>[];
  final _deferred = <void Function()>[];
  var _pumping = false;
  var _pumpAgain = false;
  var _disposed = false;
  var _nextIncidentNumber = 160;

  // ---------------------------------------------------------------- streams

  Stream<AppUser?> watchUser() => _user.watch();
  AppUser? get currentUser => _user.value;
  Stream<SignalState> watchSignal() => _signal.watch();
  Stream<LocationStatus> watchLocation() => _location.watch();
  Stream<WeatherStatus> watchWeather() => _weather.watch();

  Stream<List<SosRequest>> watchSos() => _sos.watch();

  Stream<List<QueuedRecord>> watchPending() => _sos.watch().map(
    (all) => [
      for (final s in all)
        if (s.delivery != DeliveryState.delivered)
          QueuedRecord(
            id: s.clientId,
            kind: QueuedKind.sos,
            capturedAt: s.capturedAt,
            delivery: s.delivery,
            rejectReason: s.rejectReason,
          ),
    ]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt)),
  );

  Stream<QueuedRecord> deliveries() => _deliveries.stream;

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
    return _user.value = match.first;
  }

  Future<void> signOut() async {
    await _pause();
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
    _sos.value = [sos, ..._sos.value];
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
    _sos.value = [
      for (final s in _sos.value)
        if (!(s.clientId == id && s.delivery == DeliveryState.rejected)) s,
    ];
  }

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
    _sos.value = [
      for (final s in _sos.value) s.clientId == next.clientId ? next : s,
    ];
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
          for (final s in _sos.value)
            if (s.delivery.isPending) s,
        ]..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
        for (final s in pending) {
          if (_disposed) return;
          await _advance(s.clientId);
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
          _put(now.copyWith(delivery: before));
          return;
        }
        _deliver(now);
      case SignalState.smsOnly:
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
          ),
    );
    step(
      timing.depart,
      (s) => s
          .withStatus(IncidentStatus.enRoute, _clock())
          .copyWith(etaMinutes: 7),
    );
    step(timing.arrive ~/ 2, (s) => s.copyWith(etaMinutes: 3));
    step(
      timing.arrive ~/ 2,
      (s) => s.withStatus(IncidentStatus.onScene, _clock()),
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
