import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  late DateTime now;
  late MockBackend backend;

  setUp(() {
    now = DateTime(2026, 10, 1, 15);
    backend = MockBackend(clock: () => now, latency: Duration.zero);
  });

  tearDown(() => backend.dispose());

  Future<List<Incident>> active() => backend.watchActive().first;
  Future<Incident> incident(String id) async =>
      (await active()).firstWhere((i) => i.id == id);
  Future<ResponseUnit> unit(String id) async =>
      (await backend.watchUnits().first).firstWhere((u) => u.id == id);
  Future<List<AuditEntry>> audit() => backend.watchAudit(100).first;

  /// Advances the fake clock and the simulation together.
  void advance(Duration by) {
    const step = Duration(seconds: 1);
    for (var t = Duration.zero; t < by; t += step) {
      now = now.add(step);
      backend.runTick(step);
    }
  }

  group('sign in', () {
    test('works with a demo account', () async {
      final user = await backend.signIn(
        'Dispatcher@sagip.test',
        MockSeed.demoPassword,
      );
      expect(user.role, UserRole.dispatcher);
      expect(backend.currentUser, user);
    });

    test('rejects a wrong password', () {
      expect(
        backend.signIn('dispatcher@sagip.test', 'nope'),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('dispatch actions', () {
    test('are refused when nobody is signed in', () {
      expect(
        backend.verify('INC-0147', VerificationMethod.callback),
        throwsA(isA<ActionRejected>()),
      );
    });

    test('verifying an SOS confirms it and writes the audit log', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.verify('INC-0147', VerificationMethod.callback);

      final i = await incident('INC-0147');
      expect(i.status, IncidentStatus.confirmed);
      expect(i.verificationMethod, VerificationMethod.callback);
      expect(i.events.last.kind, IncidentEventKind.verified);
      expect(i.events.last.actorName, 'R. Santos');

      final log = await audit();
      expect(log.first.action, AuditAction.verified);
      expect(log.first.targetId, 'INC-0147');
      expect(log.first.actorId, 'usr-disp-01');
    });

    test('assigning takes the unit off the available list', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit('INC-0147', 'unit-r03');

      expect((await incident('INC-0147')).status, IncidentStatus.assigned);
      expect((await unit('unit-r03')).isDispatchable, isFalse);
      expect((await audit()).first.action, AuditAction.unitAssigned);
    });

    test('a unit already taken cannot be assigned twice', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit('INC-0147', 'unit-r03');
      expect(
        backend.assignUnit('INC-0149', 'unit-r03'),
        throwsA(
          isA<ActionRejected>().having(
            (e) => e.reason,
            'reason',
            ActionRejection.unitNotAvailable,
          ),
        ),
      );
    });

    test('an override records the reason', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit(
        'INC-0147',
        'unit-r07',
        overrideReason: 'Boat needed',
      );
      final i = await incident('INC-0147');
      expect(i.suggestionOverridden, isTrue);
      expect(i.overrideReason, 'Boat needed');
      expect((await audit()).first.detail, contains('override'));
    });

    test('reassigning frees the first unit', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit('INC-0147', 'unit-r03');
      await backend.assignUnit('INC-0147', 'unit-r07');
      expect((await unit('unit-r03')).isDispatchable, isTrue);
      expect((await audit()).first.action, AuditAction.unitReassigned);
    });

    test(
      'the resident is told of each unit, the arrival, and the close',
      () async {
        await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
        expect(await backend.watchNotices('INC-0147').first, isEmpty);
        await backend.assignUnit('INC-0147', 'unit-r03');
        await backend.assignUnit('INC-0147', 'unit-r07');
        await backend.resolve('INC-0147');
        final notices = await backend.watchNotices('INC-0147').first;
        expect(
          [for (final n in notices) '${n.kind.name} ${n.unitCallSign}'],
          ['assigned R-03', 'assigned R-07', 'resolved R-07'],
        );
        // Only the first unit is texted; the resident has the app.
        expect(
          [for (final n in notices) n.sms],
          [NoticeDelivery.sent, NoticeDelivery.none, NoticeDelivery.none],
        );
        expect(notices.every((n) => n.push == NoticeDelivery.sent), isTrue);
      },
    );

    test('a false report or a crowd cluster tells no resident', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit('INC-0147', 'unit-r03');
      await backend.markFalseReport('INC-0147');
      expect(await backend.watchNotices('INC-0147').first, isEmpty);
      final cluster = (await active()).firstWhere(
        (i) => i.origin == IncidentOrigin.crowdCluster,
      );
      expect(await backend.watchNotices(cluster.id).first, isEmpty);
    });

    test('a false report leaves the queue and frees its unit', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit('INC-0147', 'unit-r03');
      await backend.markFalseReport('INC-0147');
      expect((await active()).any((i) => i.id == 'INC-0147'), isFalse);
      expect((await unit('unit-r03')).isDispatchable, isTrue);
    });

    test('actions are refused while offline', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      backend.setLink(LinkState.offline);
      expect(
        backend.confirmType('INC-0147', IncidentType.flood),
        throwsA(
          isA<ActionRejected>().having(
            (e) => e.reason,
            'reason',
            ActionRejection.offline,
          ),
        ),
      );
    });
  });

  group('simulation', () {
    test('delivers a flagged SOS after about 20 seconds', () async {
      advance(MockBackend.sosArrivesAfter);
      final sos = await incident('INC-0150');
      expect(sos.status, IncidentStatus.pendingVerification);
      expect(sos.mockLocationSuspected, isTrue);
    });

    test(
      'a third nearby report turns into a confirmed cluster (FR7)',
      () async {
        advance(MockBackend.clusterFormsAfter);
        final clusters = (await active()).where(
          (i) =>
              i.origin == IncidentOrigin.crowdCluster &&
              i.barangay == 'Barangay 412',
        );
        expect(clusters, hasLength(1));
        expect(clusters.single.status, IncidentStatus.confirmed);
        expect(clusters.single.crowdReportIds, hasLength(3));
        expect(clusters.single.suggestedType, IncidentType.flood);
      },
    );

    test('lone reports stay unclustered', () async {
      advance(MockBackend.clusterFormsAfter);
      final reports = await backend
          .watchReports(const Duration(minutes: 60))
          .first;
      expect(reports.firstWhere((r) => r.id == 'rep-205').isClustered, false);
    });

    test('an assigned unit accepts, drives, and arrives', () async {
      await backend.signIn('dispatcher@sagip.test', MockSeed.demoPassword);
      await backend.assignUnit('INC-0147', 'unit-r03');

      advance(MockBackend.acceptAfter);
      expect((await incident('INC-0147')).status, IncidentStatus.enRoute);
      expect((await unit('unit-r03')).status, UnitStatus.enRoute);

      advance(const Duration(seconds: 40));
      expect((await incident('INC-0147')).status, IncidentStatus.onScene);
      expect((await unit('unit-r03')).status, UnitStatus.onScene);

      advance(MockBackend.resolveAfterOnScene);
      expect((await active()).any((i) => i.id == 'INC-0147'), isFalse);
      expect((await unit('unit-r03')).isDispatchable, isTrue);
    });

    test('nothing moves while the connection is down', () async {
      backend.setLink(LinkState.offline);
      advance(const Duration(minutes: 1));
      expect((await active()).any((i) => i.id == 'INC-0150'), isFalse);
    });
  });
}
