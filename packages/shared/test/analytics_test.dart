import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

void main() {
  final t0 = DateTime.utc(2026, 9, 30, 6); // 2:00 PM in Manila

  Incident inc(
    String id, {
    required Duration receivedAgo,
    IncidentOrigin origin = IncidentOrigin.sos,
    ReportChannel channel = ReportChannel.app,
    IncidentType? type,
    String? unit,
    Map<IncidentEventKind, Duration> events = const {},
    Duration delay = Duration.zero,
  }) => Incident(
    id: id,
    origin: origin,
    channel: channel,
    status: IncidentStatus.assigned,
    location: const GeoPoint(14.6, 121.0),
    barangay: 'Barangay $id',
    district: 'Sampaloc',
    capturedAt: t0.subtract(receivedAgo + delay),
    receivedAt: t0.subtract(receivedAgo),
    suggestedType: type,
    assignedUnitId: unit,
    events: [
      for (final e in events.entries)
        IncidentEvent(kind: e.key, at: t0.subtract(e.value)),
    ],
  );

  // The demo timeline the RLS test checks against analytics_report, with
  // INC-0147 and INC-0146 assigned at t0 as the test does.
  final demo = [
    inc(
      'INC-0147',
      receivedAgo: const Duration(minutes: 4, seconds: 11),
      type: IncidentType.flood,
      unit: 'unit-r03',
      events: {IncidentEventKind.assigned: Duration.zero},
    ),
    inc(
      'INC-0149',
      receivedAgo: const Duration(minutes: 1, seconds: 1),
      channel: ReportChannel.sms,
    ),
    inc(
      'INC-0146',
      receivedAgo: const Duration(minutes: 6, seconds: 40),
      origin: IncidentOrigin.crowdCluster,
      type: IncidentType.flood,
      unit: 'unit-a05',
      events: {IncidentEventKind.assigned: Duration.zero},
    ),
    inc(
      'INC-0144',
      receivedAgo: const Duration(minutes: 9, seconds: 11),
      type: IncidentType.fire,
      unit: 'unit-a02',
      events: {
        IncidentEventKind.verified: const Duration(minutes: 7),
        IncidentEventKind.assigned: const Duration(seconds: 10),
      },
    ),
    inc(
      'INC-0142',
      receivedAgo: const Duration(minutes: 12, seconds: 26),
      channel: ReportChannel.sms,
      type: IncidentType.medical,
      unit: 'unit-r05',
      events: {
        IncidentEventKind.verified: const Duration(minutes: 10),
        IncidentEventKind.assigned: const Duration(minutes: 8),
      },
    ),
    inc(
      'INC-0139',
      receivedAgo: const Duration(minutes: 18, seconds: 2),
      origin: IncidentOrigin.crowdCluster,
      type: IncidentType.structural,
      unit: 'unit-r11',
      events: {
        IncidentEventKind.assigned: const Duration(minutes: 16),
        IncidentEventKind.onScene: const Duration(minutes: 4),
      },
    ),
  ];

  test('the same figures as analytics_report on the demo timeline', () {
    final r = buildAnalytics(
      incidents: demo,
      units: const {},
      from: t0.subtract(const Duration(days: 1)),
      to: t0.add(const Duration(minutes: 1)),
    );
    expect(r.incidents, 6);
    expect(r.sos, 4);
    expect(r.clusters, 2);
    expect(r.medianDispatchS, 266);
    expect(r.avgVerifyS, 138.5);
    expect(r.medianResponseS, 842);
    expect(r.sosByChannel, {ReportChannel.app: 2, ReportChannel.sms: 2});
    expect(r.byType.first.key, 'flood');
    expect(r.byType.first.count, 2);
    final r11 = r.byUnit.firstWhere((g) => g.key == 'unit-r11');
    expect(r11.avgTravelS, 720);
    expect(r.daily.single.day, DateTime(2026, 9, 30));
  });

  test('incidents outside the period are left out', () {
    final r = buildAnalytics(
      incidents: demo,
      units: const {},
      from: t0.subtract(const Duration(minutes: 5)),
      to: t0,
    );
    expect(r.incidents, 2); // INC-0147 and INC-0149
    expect(r.medianResponseS, isNull);
  });

  test('percentiles match Postgres percentile_cont', () {
    expect(median([1, 2, 3, 4]), 2.5);
    expect(median([5, null, 1]), 3);
    expect(percentile([10, 20], 0.95), 19.5);
    expect(median(const []), isNull);
  });

  test('days are Manila dates', () {
    expect(manilaDate(DateTime.utc(2026, 9, 30, 17)), DateTime(2026, 10, 1));
    expect(
      manilaDate(DateTime.utc(2026, 9, 30, 15, 59)),
      DateTime(2026, 9, 30),
    );
  });

  test('a report from the hosted project parses', () {
    final r = AnalyticsReport.fromJson({
      'to': '2026-09-30T21:43:03.478432+00:00',
      'sos': 4,
      'from': '2026-08-31T21:42:03.478432+00:00',
      'daily': [
        {'day': '2026-09-30', 'count': 6, 'avg_response_s': 842},
      ],
      'by_type': [
        {
          'key': 'flood',
          'count': 3,
          'label': 'flood',
          'avg_dispatch_s': 20646.031889,
          'avg_response_s': null,
        },
      ],
      'by_unit': [
        {
          'key': 'unit-r11',
          'count': 1,
          'label': 'R-11',
          'avg_travel_s': 720,
          'avg_response_s': 842,
        },
      ],
      'routing': [
        {'kind': 'suggestions', 'runs': 3, 'avg_ms': 12.5, 'p95_ms': 20.1},
      ],
      'clusters': 2,
      'resolved': 0,
      'incidents': 6,
      'by_barangay': [
        {
          'key': 'Barangay 105',
          'count': 1,
          'label': 'Barangay 105, Tondo',
          'avg_dispatch_s': null,
          'avg_response_s': null,
        },
      ],
      'avg_verify_s': 138.5,
      'false_reports': 0,
      'avg_dispatch_s': 8444.2127556,
      'avg_response_s': 842,
      'sos_by_channel': {'app': 2, 'sms': 2},
      'median_dispatch_s': 541,
      'median_response_s': 842,
    });
    expect(r.incidents, 6);
    expect(r.medianDispatchS, 541);
    expect(r.sosByChannel[ReportChannel.sms], 2);
    expect(r.byUnit.single.avgTravelS, 720);
    expect(r.daily.single.day, DateTime(2026, 9, 30));
    expect(r.routing.single.kind, RoutingRunKind.suggestions);
  });

  test('CSV export has every section and quotes labels with commas', () {
    final r = buildAnalytics(
      incidents: demo,
      units: const {},
      from: t0.subtract(const Duration(days: 1)),
      to: t0.add(const Duration(minutes: 1)),
      runs: [
        RoutingRun(
          kind: RoutingRunKind.route,
          platform: RoutingPlatform.web,
          computeTime: const Duration(milliseconds: 4),
          at: t0,
        ),
      ],
    );
    final csv = analyticsCsv(r);
    expect(csv, contains('median_dispatch_s,266.0'));
    expect(csv, contains('"Barangay INC-0147, Sampaloc",1'));
    expect(csv, contains('day,incidents,avg_response_s'));
    expect(csv, contains('route,1,4.0,4.0'));
  });

  test('the mock: admins only', () async {
    final backend = MockBackend(latency: Duration.zero);
    addTearDown(backend.dispose);
    final auth = MockAuthRepository(backend);
    final repo = MockAnalyticsRepository(backend);
    final now = DateTime.now();
    await auth.signIn(
      email: 'dispatcher@sagip.test',
      password: MockSeed.demoPassword,
    );
    await expectLater(
      repo.report(now.subtract(const Duration(days: 1)), now),
      throwsA(isA<ActionRejected>()),
    );
    await auth.signOut();
    await auth.signIn(
      email: 'admin@sagip.test',
      password: MockSeed.demoPassword,
    );
    final r = await repo.report(
      now.subtract(const Duration(days: 1)),
      now.add(const Duration(minutes: 1)),
    );
    expect(r.incidents, greaterThan(0));
  });

  group('SOS delivery (Objective 3)', () {
    final trial = [
      inc('A1', receivedAgo: Duration.zero, delay: const Duration(seconds: 2)),
      inc('A2', receivedAgo: Duration.zero, delay: const Duration(seconds: 4)),
      inc('A3', receivedAgo: Duration.zero, delay: const Duration(minutes: 3)),
      // The phone's clock was ahead: no delay, not a negative one.
      inc('A4', receivedAgo: Duration.zero, delay: const Duration(seconds: -5)),
      inc(
        'S1',
        receivedAgo: Duration.zero,
        channel: ReportChannel.sms,
        delay: const Duration(minutes: 20),
      ),
      inc(
        'B1',
        receivedAgo: Duration.zero,
        channel: ReportChannel.bleRelay,
        delay: const Duration(minutes: 8),
      ),
      inc(
        'C1',
        receivedAgo: Duration.zero,
        origin: IncidentOrigin.crowdCluster,
        delay: const Duration(hours: 2),
      ),
    ];

    test('per first channel, crowd clusters left out', () {
      final d = sosDelivery(trial);
      expect(d.channels.map((c) => c.channel), [
        ReportChannel.app,
        ReportChannel.sms,
        ReportChannel.bleRelay,
      ]);
      final app = d.channels.first;
      expect(app.count, 4);
      expect(app.medianS, 3); // 0, 2, 4, 180
      expect(app.maxS, 180);
      expect(app.p95S, closeTo(153.6, 1e-9));
      expect([app.within60, app.within300, app.within900], [3, 4, 4]);
      expect(d.delivered, 6);
      expect(d.deliveredWithin(60), 3);
      expect(d.deliveredWithin(300), 4);
      expect(d.deliveredWithin(900), 5);
    });

    test('in the report, the CSV, and from the database JSON', () {
      final r = buildAnalytics(
        incidents: trial,
        units: const {},
        from: t0.subtract(const Duration(hours: 1)),
        to: t0.add(const Duration(minutes: 1)),
      );
      expect(r.delivery.delivered, 6);
      expect(analyticsCsv(r), contains('sms,1,1200.0,1200.0,1200.0,0,0,0'));

      final json = AnalyticsReport.fromJson({
        'from': '2026-09-30T00:00:00Z',
        'to': '2026-10-01T00:00:00Z',
        'incidents': 0,
        'resolved': 0,
        'false_reports': 0,
        'sos': 0,
        'clusters': 0,
        'sos_delivery': {
          'channels': [
            {
              'channel': 'bleRelay',
              'count': 2,
              'median_s': 61.5,
              'p95_s': 90,
              'max_s': 93,
              'within_60': 0,
              'within_300': 2,
              'within_900': 2,
            },
          ],
          'relay_uploads': 5,
          'relayed_sos': 2,
          'relay_max_hops': 2,
        },
      });
      final ble = json.delivery.channels.single;
      expect(ble.channel, ReportChannel.bleRelay);
      expect(ble.medianS, 61.5);
      expect(ble.within(300), 2);
      expect(json.delivery.relayUploads, 5);
      expect(json.delivery.relayMaxHops, 2);
      // A report without the section (an older database) reads as empty.
      expect(
        AnalyticsReport.fromJson({
          'from': '2026-09-30T00:00:00Z',
          'to': '2026-10-01T00:00:00Z',
          'incidents': 0,
          'resolved': 0,
          'false_reports': 0,
          'sos': 0,
          'clusters': 0,
        }).delivery.channels,
        isEmpty,
      );
    });
  });
}
