import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Lets the zero-length timers in [MockSosTiming.instant] run.
Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late DateTime now;
  late MockMobileBackend backend;

  MockMobileBackend make({bool dispatch = false}) => MockMobileBackend(
    clock: () => now,
    latency: Duration.zero,
    timing: MockSosTiming.instant,
    simulateDispatch: dispatch,
  );

  setUp(() async {
    now = DateTime(2026, 9, 30, 15, 42);
    backend = make();
    await backend.signIn('maria@sagip.test', MockSeed.demoPassword);
  });

  tearDown(() => backend.dispose());

  test('an SOS is saved on the phone first, then delivered', () async {
    final sos = await backend.sendSos();
    expect(sos.delivery, DeliveryState.savedOnPhone);
    expect(sos.capturedAt, now);
    expect(sos.barangay, 'Barangay 412', reason: 'falls back to home');

    await settle();
    final delivered = (await backend.watchSos().first).single;
    expect(delivered.delivery, DeliveryState.delivered);
    expect(delivered.sentVia, ReportChannel.app);
    expect(delivered.incidentId, isNotNull);
    expect(delivered.status, IncidentStatus.pendingVerification);
    expect(await backend.watchPending().first, isEmpty);
  });

  test(
    'offline SOS keeps its capture time and syncs in capture order',
    () async {
      backend.setSignal(SignalState.smsOnly);
      final first = await backend.sendSos();
      now = now.add(const Duration(minutes: 1));
      final second = await backend.sendSos();
      await settle();

      final pending = await backend.watchPending().first;
      expect(
        [for (final r in pending) r.id],
        [first.clientId, second.clientId],
      );
      expect([
        for (final r in pending) r.delivery,
      ], everyElement(DeliveryState.sentBySms));

      final delivered = <String>[];
      final sub = backend.deliveries().listen((r) => delivered.add(r.id));
      now = now.add(const Duration(minutes: 10));
      backend.setSignal(SignalState.internet);
      await settle();
      await sub.cancel();

      expect(delivered, [first.clientId, second.clientId]);
      final all = await backend.watchSos().first;
      final byId = {for (final s in all) s.clientId: s};
      expect(byId[first.clientId]!.capturedAt, DateTime(2026, 9, 30, 15, 42));
      expect(byId[second.clientId]!.capturedAt, DateTime(2026, 9, 30, 15, 43));
      expect(byId[first.clientId]!.sentVia, ReportChannel.sms);
      expect(byId[first.clientId]!.isDelivered, isTrue);
    },
  );

  test('with no signal at all the SOS relays through nearby phones', () async {
    backend.setSignal(SignalState.noSignal);
    await backend.sendSos();
    await settle();
    final sos = (await backend.watchSos().first).single;
    expect(sos.delivery, DeliveryState.relaying);
    expect(sos.sentVia, ReportChannel.bleRelay);

    backend.setSignal(SignalState.smsOnly);
    await settle();
    final bySms = (await backend.watchSos().first).single;
    expect(bySms.delivery, DeliveryState.sentBySms);
    expect(bySms.sentVia, ReportChannel.sms);
  });

  test('the simulated dispatcher takes a delivered SOS to resolved', () async {
    backend.dispose();
    backend = make(dispatch: true);
    await backend.signIn('maria@sagip.test', MockSeed.demoPassword);

    await backend.sendSos();
    await settle();
    final sos = (await backend.watchSos().first).single;
    expect(sos.status, IncidentStatus.resolved);
    expect(sos.unitCallSign, 'R-03');
    expect(
      sos.statusTimes.keys,
      containsAll([
        IncidentStatus.pendingVerification,
        IncidentStatus.confirmed,
        IncidentStatus.assigned,
        IncidentStatus.enRoute,
        IncidentStatus.onScene,
        IncidentStatus.resolved,
      ]),
    );
  });

  test('status updates wait for internet, like realtime', () async {
    backend.dispose();
    // Instant delivery, then a dispatcher who takes a moment.
    const step = Duration(milliseconds: 20);
    backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: const MockSosTiming(
        send: Duration.zero,
        verify: step,
        assign: step,
        depart: step,
        arrive: step,
        resolve: step,
      ),
    );
    await backend.signIn('maria@sagip.test', MockSeed.demoPassword);

    await backend.sendSos();
    await settle();
    expect(
      (await backend.watchSos().first).single.status,
      IncidentStatus.pendingVerification,
    );
    backend.setSignal(SignalState.smsOnly);
    await Future<void>.delayed(step * 10);
    final offline = (await backend.watchSos().first).single;
    expect(offline.status, IncidentStatus.pendingVerification);

    backend.setSignal(SignalState.internet);
    await settle();
    final online = (await backend.watchSos().first).single;
    expect(online.status, IncidentStatus.resolved);
    expect(online.unitCallSign, 'R-03');
  });

  test('details can be added after sending', () async {
    final sos = await backend.sendSos();
    await backend.addDetails(
      sos.clientId,
      const SosDetails(type: IncidentType.flood, peopleCount: 3),
    );
    final updated = (await backend.watchSos().first).single;
    expect(updated.details.type, IncidentType.flood);
    expect(updated.details.peopleCount, 3);
  });

  test('SOS records survive a JSON round trip (for the Hive queue)', () async {
    final sos = SosRequest(
      clientId: newClientId(),
      capturedAt: DateTime(2026, 9, 30, 15, 42),
      delivery: DeliveryState.sentBySms,
      location: const GeoPoint(14.6091, 120.9925),
      accuracyMeters: 8,
      barangay: 'Barangay 412',
      district: 'Sampaloc',
      details: const SosDetails(needsExtraHelp: true, note: 'Waist-deep'),
      sentVia: ReportChannel.sms,
      sentAt: DateTime(2026, 9, 30, 15, 43),
    ).withStatus(IncidentStatus.pendingVerification, DateTime(2026, 9, 30, 16));

    final back = SosRequest.fromJson(sos.toJson());
    expect(back.clientId, sos.clientId);
    expect(back.capturedAt, sos.capturedAt);
    expect(back.delivery, DeliveryState.sentBySms);
    expect(back.location!.lat, 14.6091);
    expect(back.details.needsExtraHelp, isTrue);
    expect(back.statusTimes[IncidentStatus.pendingVerification], isNotNull);
  });

  test('client ids are version 4 UUIDs', () {
    final id = newClientId();
    expect(
      RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      ).hasMatch(id),
      isTrue,
    );
    expect(newClientId(), isNot(id));
  });
}
