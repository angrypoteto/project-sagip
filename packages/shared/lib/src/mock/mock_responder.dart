part of 'mock_mobile_backend.dart';

/// A record that goes out over the internet only: responder status updates
/// and completion reports.
@immutable
class _Outgoing {
  const _Outgoing({
    required this.id,
    required this.kind,
    required this.capturedAt,
    required this.delivery,
    this.completion,
  });

  final String id;
  final QueuedKind kind;
  final DateTime capturedAt;
  final DeliveryState delivery;
  final CompletionReport? completion;

  _Outgoing withDelivery(DeliveryState next) => _Outgoing(
    id: id,
    kind: kind,
    capturedAt: capturedAt,
    delivery: next,
    completion: completion?.withDelivery(next),
  );
}

/// The responder's side of the mock (F1 to F6): unit R-03, the
/// assignments offered to it, the drive to the scene, and what it files.
class _ResponderSim {
  _ResponderSim(this._b)
    : _state = LiveValue(
        ResponderState(
          unit: ResponseUnit(
            id: 'unit-r03',
            callSign: 'R-03',
            type: UnitType.rescueBoat,
            station: 'Sampaloc station',
            crewSize: 4,
            status: UnitStatus.available,
            location: MockMobileBackend.stationR03,
            lastLocationAt: _b._clock(),
          ),
        ),
      );

  final MockMobileBackend _b;
  final LiveValue<ResponderState> _state;
  Timer? _offerTimer;
  Timer? _mapTimer;
  Timer? _driveTimer;
  var _nextOffer = 0;
  double _stepMeters = 0;

  Stream<ResponderState> watch() => _state.watch();
  ResponderState get value => _state.value;

  // ---------------------------------------------------------------- history

  var _pastHistory = const <CompletedAssignment>[];

  /// What each report filed on this phone was about, by report id. Its
  /// delivery comes from the outbox, so the list shows "Saved on phone"
  /// until the server confirms it.
  final _filed = <String, CompletedAssignment>{};

  void seedHistory(List<CompletedAssignment> past) => _pastHistory = past;

  Stream<List<CompletedAssignment>> watchHistory() =>
      _b._outbox.watch().map((outbox) {
        final list = [
          for (final o in outbox)
            if (_filed[o.id] case final c?)
              CompletedAssignment(
                incidentId: c.incidentId,
                completedAt: c.completedAt,
                type: c.type,
                barangay: c.barangay,
                district: c.district,
                outcome: c.outcome,
                personsAssisted: c.personsAssisted,
                reportDelivery: o.delivery,
              ),
          ..._pastHistory,
        ]..sort((a, b) => b.completedAt.compareTo(a.completedAt));
        return list;
      });

  void _set({
    ResponseUnit? unit,
    Assignment? current,
    bool clearCurrent = false,
    Assignment? offer,
    bool clearOffer = false,
    DateTime? locationSentAt,
  }) {
    final s = _state.value;
    _state.value = ResponderState(
      unit: unit ?? s.unit,
      current: clearCurrent ? null : (current ?? s.current),
      offer: clearOffer ? null : (offer ?? s.offer),
      locationSentAt: locationSentAt ?? s.locationSentAt,
      gpsOn: _b._location.value.gpsOn,
    );
  }

  /// Two sample assignments near R-03, offered in turn.
  Assignment _makeOffer() {
    final now = _b._clock();
    final pick = _nextOffer++ % 2;
    return pick == 0
        ? Assignment(
            incidentId: 'INC-0147',
            offeredAt: now,
            location: const GeoPoint(14.6091, 120.9925),
            barangay: 'Barangay 412',
            district: 'Sampaloc',
            address: '1482 Dapitan St',
            channel: ReportChannel.app,
            type: IncidentType.flood,
            peopleCount: 3,
            residentNote: 'Water is waist-deep inside the house.',
            vulnerable: const [
              VulnerabilityType.seniorCitizen,
              VulnerabilityType.pwd,
            ],
          )
        : Assignment(
            incidentId: 'INC-0152',
            offeredAt: now,
            location: const GeoPoint(14.6123, 120.9968),
            barangay: 'Barangay 490',
            district: 'Sampaloc',
            address: '930 Maria Clara St',
            channel: ReportChannel.sms,
            type: IncidentType.medical,
            peopleCount: 1,
            residentNote: 'Lola fell and cannot stand.',
            vulnerable: const [VulnerabilityType.seniorCitizen],
          );
  }

  // --------------------------------------------------------------- offers

  Timer? _heartbeat;

  void onSignIn() {
    if (_b.autoOffers) _scheduleOffer(_b.timing.offerAfter);
    _startHeartbeat();
  }

  void onSignOut() {
    _offerTimer?.cancel();
    _offerTimer = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// A unit on duty keeps sharing its position (FR9), not only while
  /// driving: every five movement steps while there is internet and GPS.
  void _startHeartbeat() {
    _heartbeat?.cancel();
    final every = _b.timing.moveEvery * 5;
    if (every == Duration.zero) return;
    _heartbeat = Timer.periodic(every, (_) {
      if (_b._signal.value != SignalState.internet) return;
      if (!_b._location.value.gpsOn) return;
      final now = _b._clock();
      _set(
        unit: _state.value.unit.copyWith(lastLocationAt: now),
        locationSentAt: now,
      );
    });
    _b._timers.add(_heartbeat!);
  }

  void _scheduleOffer(Duration after) {
    _offerTimer?.cancel();
    _offerTimer = Timer(after, sendOfferNow);
    _b._timers.add(_offerTimer!);
  }

  /// Offers the next sample assignment now, if the unit is free.
  void sendOfferNow() {
    final s = _state.value;
    if (s.current != null || s.offer != null) return;
    _set(offer: _makeOffer());
  }

  /// Demo: the dispatcher reassigns or closes the current assignment.
  void dispatcherCloses() {
    final current = _state.value.current;
    if (current == null) return;
    _set(current: current.copyWith(closedByDispatcher: true));
  }

  // ------------------------------------------------------------- actions

  Future<void> accept(String incidentId) async {
    final offer = _state.value.offer;
    if (offer == null || offer.incidentId != incidentId) return;
    final now = _b._clock();
    _set(
      current: offer.copyWith(status: IncidentStatus.enRoute, acceptedAt: now),
      clearOffer: true,
      unit: _state.value.unit.copyWith(
        status: UnitStatus.enRoute,
        currentIncidentId: incidentId,
      ),
    );
    _queueStatus();
    _startMapSave();
    _startDrive();
  }

  Future<void> setStatus(UnitStatus status) async {
    final s = _state.value;
    final current = s.current;
    switch (status) {
      case UnitStatus.available:
        if (current != null) {
          throw const StatusRejected(StatusRejection.finishReportFirst);
        }
      case UnitStatus.enRoute:
        if (current == null) {
          final offer = s.offer;
          if (offer == null) {
            throw const StatusRejected(StatusRejection.noAssignment);
          }
          await accept(offer.incidentId);
        } else if (current.status == IncidentStatus.onScene) {
          throw const StatusRejected(StatusRejection.alreadyOnScene);
        }
      case UnitStatus.onScene:
        if (current == null) {
          throw const StatusRejected(StatusRejection.noAssignment);
        }
        await arrive();
    }
  }

  Future<void> arrive() async {
    final current = _state.value.current;
    if (current == null || current.status == IncidentStatus.onScene) return;
    _driveTimer?.cancel();
    final now = _b._clock();
    _set(
      current: current.copyWith(status: IncidentStatus.onScene, onSceneAt: now),
      unit: _state.value.unit.copyWith(
        status: UnitStatus.onScene,
        location: current.location,
        lastLocationAt: now,
      ),
    );
    _queueStatus();
  }

  Future<void> confirmOnScene({
    required bool realEmergency,
    String? reason,
    int? peopleFound,
  }) async {
    final current = _state.value.current;
    if (current == null) return;
    _set(
      current: current.copyWith(
        realEmergency: realEmergency,
        notRealReason: reason,
        peopleFound: peopleFound,
      ),
    );
    // The on-scene check is sent like a status update (FR8).
    _queueStatus();
  }

  Future<void> complete({
    required RescueOutcome outcome,
    required int personsAssisted,
    int housesDamaged = 0,
    int injured = 0,
    int missing = 0,
    int affectedFamilies = 0,
    String? notes,
  }) async {
    final current = _state.value.current;
    if (current == null) return;
    final now = _b._clock();
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
    _mapTimer?.cancel();
    _driveTimer?.cancel();
    _filed[report.clientId] = CompletedAssignment(
      incidentId: current.incidentId,
      completedAt: now,
      type: current.type,
      barangay: current.barangay,
      district: current.district,
      outcome: outcome,
      personsAssisted: personsAssisted,
      reportDelivery: DeliveryState.savedOnPhone,
    );
    _set(
      clearCurrent: true,
      unit: _state.value.unit.copyWith(
        status: UnitStatus.available,
        clearIncident: true,
      ),
    );
    _b._addOutgoing(
      _Outgoing(
        id: report.clientId,
        kind: QueuedKind.completionReport,
        capturedAt: now,
        delivery: DeliveryState.savedOnPhone,
        completion: report,
      ),
    );
    _queueStatus();
    if (_b.autoOffers) _scheduleOffer(_b.timing.offerAfter * 3);
  }

  void _queueStatus() => _b._addOutgoing(
    _Outgoing(
      id: newClientId(),
      kind: QueuedKind.statusUpdate,
      capturedAt: _b._clock(),
      delivery: DeliveryState.savedOnPhone,
    ),
  );

  // ------------------------------------------------ map saving and driving

  /// Simulates saving the map around the route for offline use. It only
  /// progresses while there is internet. Phase 5 does real tile caching.
  void _startMapSave() {
    _mapTimer?.cancel();
    final total = _b.timing.mapSave;
    if (total == Duration.zero) {
      _setMapSaved(1);
      return;
    }
    const steps = 5;
    _mapTimer = Timer.periodic(total ~/ steps, (t) {
      final current = _state.value.current;
      if (current == null) return t.cancel();
      if (_b._signal.value != SignalState.internet) return;
      final next = (current.mapSaved + 1 / steps).clamp(0.0, 1.0);
      _setMapSaved(next);
      if (next >= 1) t.cancel();
    });
    _b._timers.add(_mapTimer!);
  }

  void _setMapSaved(double value) {
    final current = _state.value.current;
    if (current != null) _set(current: current.copyWith(mapSaved: value));
  }

  /// Moves the unit toward the scene in a straight line (Dijkstra routes
  /// come in Phase 4) and shares its position while there is internet.
  void _startDrive() {
    _driveTimer?.cancel();
    final current = _state.value.current;
    final from = _state.value.unit.location;
    if (current == null || from == null) return;
    final every = _b.timing.moveEvery;
    final drive = _b.timing.drive;
    if (every == Duration.zero || drive == Duration.zero) {
      _moveTo(current.location);
      return;
    }
    final ticks = drive.inMilliseconds / every.inMilliseconds;
    _stepMeters = from.distanceTo(current.location) / ticks;
    _driveTimer = Timer.periodic(every, (t) {
      final s = _state.value;
      final target = s.current;
      final at = s.unit.location;
      if (target == null || at == null) return t.cancel();
      if (target.status != IncidentStatus.enRoute) return t.cancel();
      if (!_b._location.value.gpsOn) return; // "Waiting for GPS"
      final left = at.distanceTo(target.location);
      if (left <= 1) return t.cancel();
      final fraction = left <= _stepMeters ? 1.0 : _stepMeters / left;
      _moveTo(at.lerpTo(target.location, fraction));
    });
    _b._timers.add(_driveTimer!);
  }

  void _moveTo(GeoPoint point) {
    final now = _b._clock();
    final online = _b._signal.value == SignalState.internet;
    _set(
      unit: _state.value.unit.copyWith(location: point, lastLocationAt: now),
      locationSentAt: online ? now : null,
    );
  }

  /// GPS was switched on or off in the demo tools.
  void onGpsChanged() => _set();
}
