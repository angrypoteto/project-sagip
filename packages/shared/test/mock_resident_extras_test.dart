import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

/// Part 4b of the mobile mock: alerts and forecast (R7, R8), the
/// vulnerability profile (R9 to R11), past activity (R6), responder
/// history (F7), and the location picker's barangay lookup (R5).
void main() {
  late DateTime now;
  late MockMobileBackend b;

  MockMobileBackend make({bool history = false}) => MockMobileBackend(
    clock: () => now,
    latency: Duration.zero,
    timing: MockSosTiming.instant,
    simulateDispatch: false,
    autoOffers: false,
    withHistory: history,
  );

  setUp(() {
    now = DateTime(2026, 9, 30, 15, 42);
    b = make();
  });

  tearDown(() => b.dispose());

  Future<void> signInMaria() =>
      b.verifyCode('0917 000 4821', MockMobileBackend.demoCode);

  Future<ActionRejection?> rejection(Future<Object?> Function() run) async {
    try {
      await run();
      return null;
    } on ActionRejected catch (e) {
      return e.reason;
    }
  }

  group('alerts and forecast', () {
    test('newest first, unread count, and marking read', () async {
      await signInMaria();
      var feed = await b.watchAlerts().first;
      expect(feed.alerts, hasLength(4));
      expect(feed.alerts.first.source, AlertSource.mdrrmd);
      expect(feed.unread, 3);
      for (var i = 1; i < feed.alerts.length; i++) {
        expect(
          feed.alerts[i - 1].issuedAt.isAfter(feed.alerts[i].issuedAt),
          isTrue,
        );
      }
      await b.markAlertRead(feed.alerts.first.id);
      feed = await b.watchAlerts().first;
      expect(feed.unread, 2);
      expect(feed.alerts.first.read, isTrue);
    });

    test('rescue confirmations follow the resident\'s SOS (FR6)', () async {
      b.dispose();
      b = MockMobileBackend(
        clock: () => now,
        latency: Duration.zero,
        timing: MockSosTiming.instant,
        autoOffers: false,
      );
      await signInMaria();
      expect((await b.watchAlerts().first).confirmations, isEmpty);
      final feeds = <AlertFeed>[];
      final sub = b.watchAlerts().listen(feeds.add);

      await b.sendSos();
      // The mock dispatcher verifies, assigns R-03, and the unit arrives
      // and closes the SOS.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final feed = feeds.last;
      expect(
        [for (final c in feed.confirmations) c.kind],
        [
          RescueConfirmationKind.resolved,
          RescueConfirmationKind.onScene,
          RescueConfirmationKind.assigned,
        ],
        reason: 'newest first',
      );
      expect(feed.confirmations.last.unitCallSign, 'R-03');
      expect(
        feed.confirmations.every((c) => c.incidentId.startsWith('INC-')),
        isTrue,
      );
      expect(
        feed.unread,
        3 + 3,
        reason: 'three alerts and three confirmations',
      );

      await b.markConfirmationRead(feed.confirmations.last.id);
      await pumpEventQueue();
      expect(feeds.last.unread, 5);
      expect(feeds.last.confirmations.last.read, isTrue);

      // Another account on the same phone sees none of them.
      await b.signOut();
      await b.signIn(MockMobileBackend.responder.email, MockSeed.demoPassword);
      expect((await b.watchAlerts().first).confirmations, isEmpty);
      await sub.cancel();
    });

    test('forecast follows the resident barangay; some have none', () async {
      await signInMaria();
      final forecast = (await b.watchAlerts().first).forecast!;
      expect(forecast.barangay, 'Barangay 412');
      expect(forecast.risks[ForecastHazard.flood], RiskLevel.high);
      expect(forecast.topHazard, ForecastHazard.flood);
      expect(forecast.validUntil.difference(forecast.issuedAt).inHours, 72);
      expect(forecast.isSimulated, isTrue);

      await b.signOut();
      await b.register(
        fullName: 'Leo Cruz',
        phone: '0918 222 3333',
        barangay: sampleManilaBarangays.firstWhere(
          (x) => x.name == 'Barangay 461',
        ),
      );
      await b.verifyCode('0918 222 3333', MockMobileBackend.demoCode);
      expect((await b.watchAlerts().first).forecast, isNull);
    });

    test('refresh offline keeps the saved copy and its time', () async {
      await signInMaria();
      final before = (await b.watchAlerts().first).updatedAt;
      b.setSignal(SignalState.smsOnly);
      now = now.add(const Duration(minutes: 30));
      expect(await rejection(b.refreshAlerts), ActionRejection.offline);
      expect((await b.watchAlerts().first).updatedAt, before);

      b.setSignal(SignalState.internet);
      expect((await b.watchAlerts().first).updatedAt, now);
    });
  });

  group('vulnerability profile', () {
    Future<Resident> maria() async => (await b.watchResident('res-001').first)!;

    test('seeded members have ids; add, edit, remove', () async {
      await signInMaria();
      final lolo = (await maria()).household.single;
      expect(lolo.id, isNotNull);

      await b.saveMember(
        const VulnerableMember(
          label: 'Tita Rosa',
          types: [VulnerabilityType.pregnant],
        ),
      );
      var household = (await maria()).household;
      expect(household.map((m) => m.label), ['Lolo Andres', 'Tita Rosa']);

      final rosa = household.last;
      await b.saveMember(
        VulnerableMember(
          id: rosa.id,
          label: 'Tita Rosa',
          types: const [VulnerabilityType.pregnant],
          notes: 'Due in November',
        ),
      );
      household = (await maria()).household;
      expect(household, hasLength(2));
      expect(household.last.notes, 'Due in November');

      await b.removeMember(lolo.id!);
      expect((await maria()).household.single.label, 'Tita Rosa');
    });

    test(
      'withdrawing consent deletes the list; adding needs consent',
      () async {
        await signInMaria();
        await b.withdrawConsent();
        var r = await maria();
        expect(r.consentGivenAt, isNull);
        expect(r.household, isEmpty);

        expect(
          await rejection(
            () => b.saveMember(
              const VulnerableMember(
                label: 'Lolo Andres',
                types: [VulnerabilityType.seniorCitizen],
              ),
            ),
          ),
          ActionRejection.notAllowed,
        );

        await b.giveConsent();
        r = await maria();
        expect(r.consentGivenAt, now);
      },
    );

    test('changes need the internet', () async {
      await signInMaria();
      b.setSignal(SignalState.noSignal);
      expect(await rejection(b.giveConsent), ActionRejection.offline);
      expect(
        await rejection(() => b.removeMember('mem-res-001-0')),
        ActionRejection.offline,
      );
      expect((await maria()).household, hasLength(1));
    });
  });

  group('activity history', () {
    test('past SOS and reports belong to Maria only', () async {
      b.dispose();
      b = make(history: true);
      await signInMaria();
      final sos = (await b.watchSos().first).single;
      expect(sos.status, IncidentStatus.resolved);
      expect(sos.isActive, isFalse);
      final reports = await b.watchReports().first;
      expect(reports.map((r) => r.stage), [
        ReportStage.confirmed,
        ReportStage.resolved,
        ReportStage.notConfirmed,
      ]);

      await b.signOut();
      await b.register(
        fullName: 'Leo Cruz',
        phone: '0918 222 3333',
        barangay: sampleManilaBarangays.first,
      );
      await b.verifyCode('0918 222 3333', MockMobileBackend.demoCode);
      expect(await b.watchSos().first, isEmpty);
      expect(await b.watchReports().first, isEmpty);
    });

    test('a delivered report is checked against nearby reports', () async {
      await signInMaria();
      await b.submitReport(
        description: 'Flood on Dapitan St',
        fix: LocationFix(
          point: const GeoPoint(14.6091, 120.9925),
          accuracyMeters: 8,
          at: now,
        ),
      );
      await pumpEventQueue();
      final report = (await b.watchReports().first).single;
      expect(report.delivery, DeliveryState.delivered);
      expect(report.stage, ReportStage.checking);
      expect(report.incidentId, isNull, reason: 'never confirmed alone');
    });

    test('a pin chosen on the map is sent without GPS accuracy', () async {
      await signInMaria();
      await b.submitReport(
        description: 'Fallen tree',
        fix: LocationFix(
          point: const GeoPoint(14.6003, 120.9745),
          accuracyMeters: 0,
          at: now,
          manual: true,
        ),
      );
      expect((await b.watchReports().first).single.accuracyMeters, isNull);
    });
  });

  group('responder history', () {
    test('past assignments plus a new report as it syncs', () async {
      b.dispose();
      b = make(history: true);
      await b.signIn('r03@sagip.test', MockSeed.demoPassword);
      expect(await b.watchHistory().first, hasLength(5));

      b.sendOfferNow();
      await b.acceptAssignment('INC-0147');
      await b.arrive();
      b.setSignal(SignalState.noSignal);
      await b.complete(outcome: RescueOutcome.rescued, personsAssisted: 3);
      var history = await b.watchHistory().first;
      expect(history, hasLength(6));
      expect(history.first.incidentId, 'INC-0147');
      expect(history.first.reportDelivery, DeliveryState.savedOnPhone);

      b.setSignal(SignalState.internet);
      await pumpEventQueue();
      history = await b.watchHistory().first;
      expect(history.first.reportDelivery, DeliveryState.delivered);
    });
  });

  test('the nearest sample barangay, only when close', () {
    expect(
      nearestBarangay(const GeoPoint(14.6093, 120.9927))?.name,
      'Barangay 412',
    );
    expect(nearestBarangay(const GeoPoint(14.5500, 121.0500)), isNull);
  });

  test('new fields survive JSON', () {
    final alert = PublicAlert(
      id: 'a1',
      source: AlertSource.phivolcs,
      level: AlertLevel.info,
      title: 'T',
      body: 'B',
      issuedAt: now,
      guidance: const ['Wear a mask'],
      barangays: const ['Barangay 412'],
    );
    final back = PublicAlert.fromJson(alert.toJson());
    expect(back.guidance, ['Wear a mask']);
    expect(back.barangays, ['Barangay 412']);
    expect(back.issuedAt, now);

    final forecast = BarangayForecast(
      barangay: 'Barangay 700',
      district: 'Malate',
      issuedAt: now,
      validUntil: now.add(const Duration(hours: 72)),
      risks: const {ForecastHazard.stormSurge: RiskLevel.high},
    );
    expect(BarangayForecast.fromJson(forecast.toJson()).risks, forecast.risks);

    final done = CompletedAssignment(
      incidentId: 'INC-0139',
      completedAt: now,
      barangay: 'Barangay 105',
      district: 'Tondo',
      outcome: RescueOutcome.rescued,
      personsAssisted: 4,
      reportDelivery: DeliveryState.sending,
    );
    expect(
      CompletedAssignment.fromJson(done.toJson()).reportDelivery,
      DeliveryState.sending,
    );

    const member = VulnerableMember(
      id: '42',
      label: 'Lolo',
      types: [VulnerabilityType.pwd],
    );
    expect(VulnerableMember.fromJson(member.toJson()).id, '42');
  });
}
