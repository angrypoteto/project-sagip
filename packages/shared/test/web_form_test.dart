import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Matcher refused(ReportRejection reason) =>
    throwsA(isA<ReportRejected>().having((e) => e.reason, 'reason', reason));

Matcher rejected(ActionRejection reason) =>
    throwsA(isA<ActionRejected>().having((e) => e.reason, 'reason', reason));

void main() {
  const binondo = GeoPoint(14.6003, 120.9745);
  var now = DateTime(2026, 10, 1, 15, 42);
  late MockMobileBackend backend;
  late MockWebReportRepository web;

  setUp(() async {
    now = DateTime(2026, 10, 1, 15, 42);
    backend = MockMobileBackend(
      clock: () => now,
      latency: Duration.zero,
      timing: MockSosTiming.instant,
      simulateDispatch: false,
      autoOffers: false,
    );
    web = MockWebReportRepository(backend);
    await backend.sendCode('0917 000 4821');
    await backend.verifyCode('0917 000 4821', MockMobileBackend.demoCode);
  });

  tearDown(() => backend.dispose());

  Future<HazardReport> send(String id, {GeoPoint at = binondo}) => web.submit(
    clientId: id,
    capturedAt: now,
    description: ' Baha sa kanto ',
    location: at,
    type: IncidentType.flood,
  );

  group('the web form follows the same rules as submit_crowd_report', () {
    test(
      'a report is delivered at once, marked as from the web form',
      () async {
        expect((await web.watchQuota().first).remaining, 5);
        final sent = await send('00000000-0000-4000-8000-0000000006a1');
        expect(sent.delivery, DeliveryState.delivered);
        expect(sent.serverId, 'rep-400');
        expect(sent.source, ReportChannel.webForm);
        expect(
          sent.stage,
          ReportStage.checking,
          reason: 'never confirmed alone',
        );
        expect(sent.description, 'Baha sa kanto');
        // No barangay chosen: the resident's own, as the server does.
        expect(sent.barangay, 'Barangay 412');

        final mine = await web.watchMine().first;
        expect(mine.single.clientId, sent.clientId);
        final quota = await web.watchQuota().first;
        expect((quota.limit, quota.used, quota.remaining), (5, 1, 4));
        expect(quota.resetsAt, isNull);
      },
    );

    test('the same report sent again is stored once', () async {
      final first = await send('00000000-0000-4000-8000-0000000006a1');
      final again = await send('00000000-0000-4000-8000-0000000006a1');
      expect(again.serverId, first.serverId);
      expect(await web.watchMine().first, hasLength(1));
    });

    test('outside Manila, empty, and offline are refused', () async {
      await expectLater(
        send(newClientId(), at: const GeoPoint(14.40, 121.20)),
        refused(ReportRejection.outsideManila),
      );
      await expectLater(
        web.submit(
          clientId: newClientId(),
          capturedAt: now,
          description: '   ',
          location: binondo,
        ),
        refused(ReportRejection.emptyDescription),
      );
      backend.setSignal(SignalState.smsOnly);
      await expectLater(send(newClientId()), rejected(ActionRejection.offline));
      expect(await web.watchMine().first, isEmpty);
    });

    test('the hourly limit counts the app and the web form together', () async {
      // Two from the app, three from the web form.
      for (var i = 0; i < 2; i++) {
        await backend.submitReport(
          description: 'From the app $i',
          fix: LocationFix(point: binondo, accuracyMeters: 8, at: now),
        );
      }
      for (var i = 0; i < 3; i++) {
        await send(newClientId());
      }
      await expectLater(
        send(newClientId()),
        refused(ReportRejection.rateLimited),
      );
      final quota = await web.watchQuota().first;
      expect(quota.remaining, 0);
      expect(quota.resetsAt, now.add(const Duration(hours: 1)));

      // An hour later the slots are free again.
      now = now.add(const Duration(hours: 1, minutes: 1));
      expect((await web.watchQuota().first).remaining, 5);
      await send(newClientId());
    });

    test('a suspended account cannot send, and the quota says so', () async {
      backend.setResidentSuspended('res-001', suspended: true);
      expect((await web.watchQuota().first).suspended, isTrue);
      await expectLater(
        send(newClientId()),
        refused(ReportRejection.accountSuspended),
      );
      backend.setResidentSuspended('res-001', suspended: false);
      expect((await web.watchQuota().first).suspended, isFalse);
      await send(newClientId());
    });

    test('signed out, nothing is sent', () async {
      await backend.signOut();
      await expectLater(
        send(newClientId()),
        rejected(ActionRejection.notAllowed),
      );
    });
  });

  group('rows from the database', () {
    test('my_report_quota parses', () {
      final open = ReportQuota.fromJson({
        'limit': 5,
        'used': 1,
        'remaining': 4,
        'resets_at': null,
        'suspended': false,
      });
      expect((open.limit, open.used, open.remaining), (5, 1, 4));
      expect(open.resetsAt, isNull);
      final full = ReportQuota.fromJson({
        'limit': 1,
        'used': 1,
        'remaining': 0,
        'resets_at': '2026-10-01T09:13:19.000000+00:00',
        'suspended': true,
      });
      expect(full.remaining, 0);
      expect(full.resetsAt!.toUtc(), DateTime.utc(2026, 10, 1, 9, 13, 19));
      expect(full.suspended, isTrue);
      expect(ReportQuota.fromJson(full.toJson()).resetsAt, full.resetsAt);
    });

    test('my_crowd_reports carries the channel', () {
      final row = {
        'client_id': '00000000-0000-4000-8000-0000000006a1',
        'captured_at': '2026-10-01T08:13:19+00:00',
        'description': 'Baha sa kanto',
        'type': 'flood',
        'latitude': 14.6003,
        'longitude': 120.9745,
        'accuracy_m': null,
        'barangay': 'Barangay 287',
        'district': 'Binondo',
        'delivery': 'delivered',
        'delivered_at': '2026-10-01T08:13:20+00:00',
        'server_id': 'rep-301',
        'stage': 'checking',
        'incident_id': null,
        'source': 'webForm',
      };
      final report = HazardReport.fromJson(row);
      expect(report.source, ReportChannel.webForm);
      expect(HazardReport.fromJson(report.toJson()).source, report.source);
      // Rows saved on a phone before this column existed have no source.
      expect(HazardReport.fromJson({...row}..remove('source')).source, isNull);
    });
  });

  group('the hourly limit is an A3 setting', () {
    late MockBackend dashboard;
    late MockSettingsRepository settings;
    late MockAuthRepository auth;

    setUp(() {
      dashboard = MockBackend(latency: Duration.zero);
      settings = MockSettingsRepository(dashboard);
      auth = MockAuthRepository(dashboard);
    });

    tearDown(() => dashboard.dispose());

    test('an admin changes it within its range; it is audited', () async {
      await auth.signIn(
        email: 'admin@sagip.test',
        password: MockSeed.demoPassword,
      );
      final before = await settings.watch().first;
      final limit = before.firstWhere((s) => s.key == reportsPerHourKey);
      expect((limit.value, limit.min, limit.max), (5, 1, 30));
      expect(limit.category, 'reports');

      await expectLater(
        settings.set(reportsPerHourKey, 0),
        rejected(ActionRejection.invalidValue),
      );
      await settings.set(reportsPerHourKey, 8);
      final after = await settings.watch().first;
      expect(after.firstWhere((s) => s.key == reportsPerHourKey).value, 8);
      // The priority rules ignore settings from other groups.
      expect(PriorityRules.fromSettings(after).sosPoints, 50);

      final audit = await MockAuditRepository(dashboard).watchRecent().first;
      final entry = audit.firstWhere(
        (e) => e.action == AuditAction.settingChanged,
      );
      expect(entry.targetId, reportsPerHourKey);
      expect(entry.detail, '5 → 8');
    });

    test('a dispatcher cannot change it', () async {
      await auth.signIn(
        email: 'dispatcher@sagip.test',
        password: MockSeed.demoPassword,
      );
      await expectLater(
        settings.set(reportsPerHourKey, 8),
        rejected(ActionRejection.notAllowed),
      );
    });
  });
}
