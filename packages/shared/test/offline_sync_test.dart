import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// A server whose network can be cut, that records what it was sent, and
/// whose read streams the test controls.
class FakeServer implements MobileServer {
  var reachable = true;
  final calls = <String>[];
  final sosList = StreamController<List<SosRequest>>.broadcast();
  final reportList = StreamController<List<HazardReport>>.broadcast();
  final unit = StreamController<ResponseUnit?>.broadcast();
  final jobs = StreamController<List<Assignment>>.broadcast();
  final history = StreamController<List<CompletedAssignment>>.broadcast();

  /// Refusal to throw for the next report.
  ReportRejection? refuseNextReport;
  var _incident = 200;

  void _net() {
    if (!reachable) throw const ActionRejected(ActionRejection.offline);
  }

  @override
  Future<String> submitSos(SosRequest sos) async {
    _net();
    calls.add('sos ${sos.clientId}');
    return 'INC-0${_incident++}';
  }

  @override
  Future<void> addSosDetails(String clientId, SosDetails details) async {
    _net();
    calls.add('details $clientId');
  }

  @override
  Future<String> submitReport(HazardReport report) async {
    _net();
    final refuse = refuseNextReport;
    refuseNextReport = null;
    if (refuse != null) throw ReportRejected(refuse);
    calls.add('report ${report.description}');
    return 'rep-${report.description}';
  }

  @override
  Future<void> accept(String incidentId, DateTime capturedAt) async {
    _net();
    calls.add('accept $incidentId');
  }

  @override
  Future<void> arrive(String incidentId, DateTime capturedAt) async {
    _net();
    calls.add('arrive $incidentId');
  }

  @override
  Future<void> confirmOnScene(
    String incidentId, {
    required bool realEmergency,
    required DateTime capturedAt,
    String? reason,
    int? peopleFound,
  }) async {
    _net();
    calls.add('confirm $incidentId $realEmergency');
  }

  @override
  Future<void> setStatus(UnitStatus status, DateTime capturedAt) async {
    _net();
    calls.add('status ${status.name}');
  }

  @override
  Future<void> submitCompletion(CompletionReport report) async {
    _net();
    calls.add('completion ${report.incidentId}');
  }

  @override
  Future<void> updateLocation(GeoPoint point, DateTime capturedAt) async {
    _net();
    calls.add('location ${point.lat}');
  }

  @override
  Stream<List<SosRequest>> watchMySos() => sosList.stream;
  @override
  Stream<List<HazardReport>> watchMyReports() => reportList.stream;
  @override
  Stream<ResponseUnit?> watchUnit() => unit.stream;
  @override
  Stream<List<Assignment>> watchAssignments() => jobs.stream;
  @override
  Stream<List<CompletedAssignment>> watchHistory() => history.stream;
}

void main() {
  late DateTime now;
  late FakeServer server;
  late MemoryLocalStore store;
  late StreamController<bool> online;
  late String? account;
  late SyncEngine engine;

  SyncEngine makeEngine() => SyncEngine(
    store: store,
    sender: ServerSender(server),
    online: online.stream,
    account: () => account,
    clock: () => now,
    retryDelay: (_) => const Duration(milliseconds: 10),
  );

  setUp(() {
    now = DateTime(2026, 9, 30, 15, 42);
    server = FakeServer();
    store = MemoryLocalStore();
    online = StreamController<bool>.broadcast();
    account = 'res-001';
    engine = makeEngine();
  });

  tearDown(() => engine.dispose());

  Future<void> goOnline(bool on) async {
    online.add(on);
    await pumpEventQueue();
  }

  OutboxEntry entry(
    String id,
    OutboxAction action,
    Map<String, Object?> payload, {
    String who = 'res-001',
    int minutes = 0,
  }) => OutboxEntry(
    id: id,
    action: action,
    accountId: who,
    capturedAt: now.add(Duration(minutes: minutes)),
    payload: payload,
  );

  SosRequest sos(String id, {int minutes = 0}) => SosRequest(
    clientId: id,
    capturedAt: now.add(Duration(minutes: minutes)),
    delivery: DeliveryState.savedOnPhone,
    location: const GeoPoint(14.6091, 120.9925),
    accuracyMeters: 8,
  );

  HazardReport report(String text, {int minutes = 0}) => HazardReport(
    clientId: 'r-$text',
    capturedAt: now.add(Duration(minutes: minutes)),
    description: text,
    delivery: DeliveryState.savedOnPhone,
    location: const GeoPoint(14.6091, 120.9925),
  );

  group('sync engine', () {
    test('saved first; sent in capture order once online; notices', () async {
      final notices = <QueuedRecord>[];
      final sub = engine.deliveries().listen(notices.add);
      await goOnline(false);

      await engine.add(
        entry(
          'r-b',
          OutboxAction.crowdReport,
          report('b', minutes: 2).toJson(),
          minutes: 2,
        ),
      );
      await engine.add(
        entry(
          's-a',
          OutboxAction.sos,
          sos('s-a', minutes: 1).toJson(),
          minutes: 1,
        ),
      );
      await engine.add(
        entry('d-c', OutboxAction.sosDetails, {
          'client_id': 's-a',
          'details': const SosDetails(peopleCount: 2).toJson(),
        }, minutes: 3),
      );
      await pumpEventQueue();
      expect(server.calls, isEmpty);
      expect(
        engine.entries.map((e) => e.delivery),
        everyElement(DeliveryState.savedOnPhone),
      );
      expect(store.outbox, hasLength(3), reason: 'saved on the phone');

      await goOnline(true);
      expect(server.calls, ['sos s-a', 'report b', 'details s-a']);
      expect(
        engine.entries.map((e) => e.delivery),
        everyElement(DeliveryState.delivered),
      );
      expect(engine.entries.first.serverId, 'INC-0200');
      expect(
        engine.entries.first.capturedAt,
        now.add(const Duration(minutes: 1)),
        reason: 'capture time kept',
      );
      expect(notices.map((n) => n.waitedOffline), everyElement(isTrue));
      await sub.cancel();
    });

    test('a record sent at once gets no "was delivered" notice', () async {
      final notices = <QueuedRecord>[];
      final sub = engine.deliveries().listen(notices.add);
      await goOnline(true);
      await engine.add(entry('s-a', OutboxAction.sos, sos('s-a').toJson()));
      await pumpEventQueue();
      expect(notices.single.waitedOffline, isFalse);
      await sub.cancel();
    });

    test('a network failure stops the run, keeps the order, retries', () async {
      await goOnline(true);
      server.reachable = false;
      await engine.add(entry('s-a', OutboxAction.sos, sos('s-a').toJson()));
      await engine.add(
        entry(
          'r-b',
          OutboxAction.crowdReport,
          report('b').toJson(),
          minutes: 1,
        ),
      );
      await pumpEventQueue();
      expect(server.calls, isEmpty);
      expect(engine.entries.first.attempts, greaterThan(0));
      expect(engine.entries.first.delivery, DeliveryState.savedOnPhone);

      server.reachable = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pumpEventQueue();
      expect(server.calls, ['sos s-a', 'report b']);
    });

    test('a refused record is kept as rejected and the rest go on', () async {
      await goOnline(true);
      server.refuseNextReport = ReportRejection.outsideManila;
      await engine.add(
        entry('r-a', OutboxAction.crowdReport, report('a').toJson()),
      );
      await engine.add(
        entry('s-b', OutboxAction.sos, sos('s-b').toJson(), minutes: 1),
      );
      await pumpEventQueue();
      final a = engine.entries.firstWhere((e) => e.id == 'r-a');
      expect(a.delivery, DeliveryState.rejected);
      expect(a.rejectReason, 'outsideManila');
      expect(server.calls, ['sos s-b']);

      await engine.remove('r-a');
      expect(engine.entries.map((e) => e.id), ['s-b']);
      expect(store.outbox.map((e) => e.id), ['s-b']);
    });

    test("another account's records wait until it signs in again", () async {
      await goOnline(true);
      await engine.add(
        entry('s-x', OutboxAction.sos, sos('s-x').toJson(), who: 'res-002'),
      );
      await pumpEventQueue();
      expect(server.calls, isEmpty);
      account = 'res-002';
      engine.accountChanged();
      await pumpEventQueue();
      expect(server.calls, ['sos s-x']);
    });

    test(
      'after a restart: a cut-off send is retried, old deliveries pruned',
      () async {
        await store.putEntry(
          entry(
            's-a',
            OutboxAction.sos,
            sos('s-a').toJson(),
          ).copyWith(delivery: DeliveryState.sending),
        );
        await store.putEntry(
          entry('s-old', OutboxAction.sos, sos('s-old').toJson()).copyWith(
            delivery: DeliveryState.delivered,
            deliveredAt: now.subtract(const Duration(days: 2)),
          ),
        );
        await engine.dispose();
        engine = makeEngine();
        expect(engine.entries.single.id, 's-a');
        expect(engine.entries.single.delivery, DeliveryState.savedOnPhone);
        await goOnline(true);
        expect(server.calls, ['sos s-a']);
      },
    );

    test('entries survive a round trip through JSON', () {
      final e = entry(
        's-a',
        OutboxAction.sos,
        sos('s-a').toJson(),
      ).copyWith(attempts: 2, waited: true);
      final back = OutboxEntry.fromJson(
        (jsonDecode(jsonEncode(e.toJson())) as Map).cast<String, Object?>(),
      );
      expect(back.action, OutboxAction.sos);
      expect(back.attempts, 2);
      expect(back.capturedAt, now);
      expect(SosRequest.fromJson(back.payload).accuracyMeters, 8);
    });
  });

  group('resident repositories', () {
    test('an SOS shows at once, offline, then as the server has it', () async {
      final repo = OutboxSosRepository(
        engine: engine,
        server: server,
        store: store,
        account: () => account,
        clock: () => now,
      );
      final seen = <List<SosRequest>>[];
      final sub = repo.watchMine().listen(seen.add);
      await goOnline(false);
      server.sosList.addError(const ActionRejected(ActionRejection.offline));
      await pumpEventQueue();

      final sent = await repo.send(
        fix: LocationFix(
          point: const GeoPoint(14.6091, 120.9925),
          accuracyMeters: 8,
          at: now,
          mockProvider: true,
        ),
      );
      await repo.addDetails(sent.clientId, const SosDetails(peopleCount: 4));
      await pumpEventQueue();
      expect(seen.last.single.delivery, DeliveryState.savedOnPhone);
      expect(seen.last.single.details.peopleCount, 4);
      expect(seen.last.single.mockLocationSuspected, isTrue);

      await goOnline(true);
      expect(seen.last.single.delivery, DeliveryState.delivered);
      expect(seen.last.single.status, IncidentStatus.pendingVerification);
      expect(seen.last.single.incidentId, 'INC-0200');

      server.sosList.add([
        sent
            .copyWith(delivery: DeliveryState.delivered, incidentId: 'INC-0200')
            .withStatus(IncidentStatus.confirmed, now),
      ]);
      await pumpEventQueue();
      expect(seen.last.single.status, IncidentStatus.confirmed);
      expect(store.read('sos:res-001'), isA<String>(), reason: 'saved copy');
      await sub.cancel();
    });

    test('report checks on the phone, including the hourly limit', () async {
      final repo = OutboxHazardReportRepository(
        engine: engine,
        server: server,
        store: store,
        account: () => account,
        clock: () => now,
      );
      final fix = LocationFix(
        point: const GeoPoint(14.6091, 120.9925),
        accuracyMeters: 8,
        at: now,
      );
      Future<ReportRejection?> refusal(Future<Object?> Function() f) async {
        try {
          await f();
          return null;
        } on ReportRejected catch (e) {
          return e.reason;
        }
      }

      expect(
        await refusal(() => repo.submit(description: '  ', fix: fix)),
        ReportRejection.emptyDescription,
      );
      expect(
        await refusal(() => repo.submit(description: 'Flood')),
        ReportRejection.noLocation,
      );
      expect(
        await refusal(
          () => repo.submit(
            description: 'Flood',
            fix: LocationFix(
              point: const GeoPoint(14.40, 121.20),
              accuracyMeters: 8,
              at: now,
            ),
          ),
        ),
        ReportRejection.outsideManila,
      );
      // Two already on the server this hour, three made on the phone.
      await store.write(
        'reports:res-001',
        jsonEncode([
          report(
            'x',
            minutes: -10,
          ).copyWith(delivery: DeliveryState.delivered).toJson(),
          report(
            'y',
            minutes: -20,
          ).copyWith(delivery: DeliveryState.delivered).toJson(),
        ]),
      );
      for (var i = 0; i < 3; i++) {
        await repo.submit(description: 'Flood $i', fix: fix);
      }
      expect(
        await refusal(() => repo.submit(description: 'Flood 4', fix: fix)),
        ReportRejection.rateLimited,
      );
    });

    test('merging keeps the server copy and adds what is on the phone', () {
      final merged = OutboxHazardReportRepository.mergeReports(
        [
          report('a').copyWith(
            delivery: DeliveryState.delivered,
            stage: ReportStage.confirmed,
          ),
        ],
        [
          entry('r-a', OutboxAction.crowdReport, report('a').toJson()),
          entry(
            'r-b',
            OutboxAction.crowdReport,
            report('b', minutes: 1).toJson(),
          ),
          entry(
            'r-c',
            OutboxAction.crowdReport,
            report('c').toJson(),
            who: 'res-002',
          ),
        ],
        'res-001',
      );
      expect(merged.map((r) => r.description), ['b', 'a']);
      expect(merged.last.stage, ReportStage.confirmed);
      expect(merged.first.delivery, DeliveryState.savedOnPhone);
    });
  });

  group('responder repository', () {
    const unitR03 = ResponseUnit(
      id: 'unit-r03',
      callSign: 'R-03',
      type: UnitType.rescueBoat,
      station: 'Sampaloc station',
      crewSize: 4,
      status: UnitStatus.available,
    );
    Assignment job(IncidentStatus status) => Assignment(
      incidentId: 'INC-0147',
      offeredAt: now,
      location: const GeoPoint(14.6091, 120.9925),
      barangay: 'Barangay 412',
      district: 'Sampaloc',
      channel: ReportChannel.app,
      type: IncidentType.flood,
      status: status,
    );

    test(
      'a job worked offline: accept, arrive, report; history waits',
      () async {
        account = 'rsp-r03';
        final repo = OutboxResponderRepository(
          engine: engine,
          server: server,
          store: store,
          account: () => account,
          clock: () => now,
        );
        final states = <ResponderState>[];
        final history = <List<CompletedAssignment>>[];
        final sub = repo.watch().listen(states.add);
        final hsub = repo.watchHistory().listen(history.add);
        await goOnline(false);
        server.unit.add(unitR03);
        server.jobs.add([job(IncidentStatus.assigned)]);
        server.history.addError(const ActionRejected(ActionRejection.offline));
        await pumpEventQueue();
        expect(states.last.offer?.incidentId, 'INC-0147');
        expect(states.last.current, isNull);

        await repo.accept('INC-0147');
        await pumpEventQueue();
        expect(states.last.current?.status, IncidentStatus.enRoute);
        expect(states.last.unit.status, UnitStatus.enRoute);

        await expectLater(
          repo.setStatus(UnitStatus.available),
          throwsA(isA<StatusRejected>()),
        );
        await repo.arrive();
        await pumpEventQueue();
        expect(states.last.current?.status, IncidentStatus.onScene);
        await repo.confirmOnScene(realEmergency: true, peopleFound: 2);
        await repo.complete(outcome: RescueOutcome.rescued, personsAssisted: 2);
        await pumpEventQueue();
        expect(states.last.current, isNull);
        expect(states.last.unit.status, UnitStatus.available);
        expect(history.last.single.reportDelivery, DeliveryState.savedOnPhone);
        expect(history.last.single.barangay, 'Barangay 412');
        expect(server.calls, isEmpty);

        await goOnline(true);
        expect(server.calls, [
          'accept INC-0147',
          'arrive INC-0147',
          'confirm INC-0147 true',
          'completion INC-0147',
        ]);
        expect(history.last.single.reportDelivery, DeliveryState.delivered);
        await sub.cancel();
        await hsub.cancel();
      },
    );

    test(
      'a job the dispatcher closes stays with a banner until Available',
      () async {
        account = 'rsp-r03';
        final repo = OutboxResponderRepository(
          engine: engine,
          server: server,
          store: store,
          account: () => account,
          clock: () => now,
        );
        final states = <ResponderState>[];
        final sub = repo.watch().listen(states.add);
        await goOnline(true);
        server.unit.add(unitR03.copyWith(status: UnitStatus.enRoute));
        server.jobs.add([job(IncidentStatus.enRoute)]);
        await pumpEventQueue();
        expect(states.last.current?.closedByDispatcher, isFalse);

        server.jobs.add(const []);
        await pumpEventQueue();
        expect(states.last.current?.closedByDispatcher, isTrue);

        await repo.setStatus(UnitStatus.available);
        await pumpEventQueue();
        expect(states.last.current, isNull);
        expect(server.calls, ['status available']);
        await sub.cancel();
      },
    );
  });

  group('saved copies', () {
    test(
      'the saved copy shows first, then the server copy replaces it',
      () async {
        await store.write(
          'weather',
          jsonEncode(
            WeatherStatus(
              signalLevel: 1,
              rainfallMmPerHour: 5,
              issuedAt: now,
            ).toJson(),
          ),
        );
        final source = StreamController<WeatherStatus>();
        final repo = CachedWeatherRepository(_Weather(source.stream), store);
        final seen = <WeatherStatus>[];
        final sub = repo.watchCurrent().listen(seen.add);
        await pumpEventQueue();
        expect(seen.single.signalLevel, 1);
        source.add(
          WeatherStatus(signalLevel: 3, rainfallMmPerHour: 30, issuedAt: now),
        );
        await pumpEventQueue();
        expect(seen.last.signalLevel, 3);
        expect(store.read('weather'), contains('"signal_level":3'));
        await sub.cancel();
      },
    );

    test('an alert opened offline shows as read', () async {
      final source = StreamController<AlertFeed>();
      final inner = _Alerts(source.stream);
      final repo = CachedAlertRepository(inner, store, () => 'res-001');
      final seen = <AlertFeed>[];
      final sub = repo.watch().listen(seen.add);
      source.add(
        AlertFeed(
          alerts: [
            PublicAlert(
              id: 'a1',
              source: AlertSource.pagasa,
              level: AlertLevel.warning,
              title: 'T',
              body: 'B',
              issuedAt: now,
            ),
          ],
          updatedAt: now,
        ),
      );
      await pumpEventQueue();
      expect(seen.last.unread, 1);
      await repo.markRead('a1');
      await pumpEventQueue();
      expect(seen.last.unread, 0);
      await sub.cancel();
    });
  });

  test(
    'position sharing: at most every 15 s, only online, heartbeat',
    () async {
      var clock = now;
      final fixes = StreamController<LocationStatus>();
      final sharer = ResponderLocationSharer(
        server: server,
        location: fixes.stream,
        online: online.stream,
        clock: () => clock,
        every: const Duration(milliseconds: 40),
      )..start();
      LocationStatus at(int ms, double lat) => LocationStatus(
        gpsOn: true,
        lastFix: LocationFix(
          point: GeoPoint(lat, 120.99),
          accuracyMeters: 5,
          at: now.add(Duration(milliseconds: ms)),
        ),
      );
      fixes.add(at(0, 14.60));
      await pumpEventQueue();
      expect(server.calls, isEmpty, reason: 'offline');

      await goOnline(true);
      expect(server.calls, ['location 14.6'], reason: 'sent on reconnect');
      clock = now.add(const Duration(milliseconds: 10));
      fixes.add(at(10, 14.61));
      await pumpEventQueue();
      expect(server.calls, hasLength(1), reason: 'too soon after the last');

      // Standing still: the heartbeat repeats the position.
      clock = now.add(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      await pumpEventQueue();
      expect(server.calls.last, 'location 14.61');
      await sharer.stop();
    },
  );
}

class _Weather implements WeatherRepository {
  _Weather(this._s);
  final Stream<WeatherStatus> _s;
  @override
  Stream<WeatherStatus> watchCurrent() => _s;
}

class _Alerts implements AlertRepository {
  _Alerts(this._s);
  final Stream<AlertFeed> _s;
  @override
  Stream<AlertFeed> watch() => _s;
  @override
  Future<void> refresh() async {}
  @override
  Future<void> markRead(String alertId) async =>
      throw const ActionRejected(ActionRejection.offline);
}
