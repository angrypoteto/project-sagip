import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Incident incident({
  String id = 'INC-1',
  IncidentOrigin origin = IncidentOrigin.sos,
  IncidentStatus status = IncidentStatus.pendingVerification,
  Duration waiting = Duration.zero,
  List<VulnerabilityType> vulnerable = const [],
  bool mockLocation = false,
}) {
  final now = DateTime(2026, 10, 1, 15);
  return Incident(
    id: id,
    origin: origin,
    channel: ReportChannel.app,
    status: status,
    location: const GeoPoint(14.6, 121.0),
    barangay: 'Barangay 1',
    district: 'Tondo',
    capturedAt: now.subtract(waiting),
    receivedAt: now.subtract(waiting),
    vulnerable: vulnerable,
    mockLocationSuspected: mockLocation,
  );
}

void main() {
  final now = DateTime(2026, 10, 1, 15);
  const rules = PriorityRules();

  test('an SOS from a vulnerable household waiting 4 minutes is critical', () {
    final b = rules.score(
      incident(
        waiting: const Duration(minutes: 4),
        vulnerable: [VulnerabilityType.pwd],
      ),
      now,
    );
    expect(b.total, 50 + 30 + 8);
    expect(b.severity, Severity.critical);
    expect(
      b.factors.map((f) => f.kind),
      containsAll([
        PriorityFactorKind.sos,
        PriorityFactorKind.vulnerable,
        PriorityFactorKind.waiting,
      ]),
    );
  });

  test('waiting points are capped', () {
    final b = rules.score(incident(waiting: const Duration(hours: 2)), now);
    final waiting = b.factors.firstWhere(
      (f) => f.kind == PriorityFactorKind.waiting,
    );
    expect(waiting.points, rules.maxWaitingPoints);
  });

  test('a mock location lowers the score but keeps the SOS on the board', () {
    final b = rules.score(incident(mockLocation: true), now);
    expect(b.total, 50 - 20);
    expect(b.severity, Severity.normal);
  });

  test('queue order: needs dispatch first, then by score, then by waiting', () {
    final assignedVulnerable = incident(
      id: 'assigned',
      status: IncidentStatus.assigned,
      vulnerable: [VulnerabilityType.seniorCitizen],
    );
    final plainSos = incident(id: 'plain', waiting: const Duration(minutes: 1));
    final vulnerableSos = incident(
      id: 'vulnerable',
      vulnerable: [VulnerabilityType.pregnant],
    );
    final cluster = incident(
      id: 'cluster',
      origin: IncidentOrigin.crowdCluster,
      status: IncidentStatus.confirmed,
      waiting: const Duration(minutes: 2),
    );
    final ordered = rules.order([
      assignedVulnerable,
      plainSos,
      vulnerableSos,
      cluster,
    ], now);
    expect(ordered.map((i) => i.id), [
      'vulnerable', // 80
      'plain', // 52
      'cluster', // 44
      'assigned', // already has a unit
    ]);
  });

  group('A3 settings', () {
    test('rules from the default settings score like the defaults', () {
      final fromDb = PriorityRules.fromSettings(defaultPrioritySettings);
      expect(fromDb.toSettings(), rules.toSettings());
      expect(PriorityRules.settingKeys.toSet(), {
        for (final s in defaultPrioritySettings) s.key,
      });
    });

    // The same fixtures as the RLS test's checks on incident_board, so the
    // Dart rules and private.priority_breakdown agree.
    test('matches the database on the demo incidents', () {
      final cluster = rules.score(
        incident(
          origin: IncidentOrigin.crowdCluster,
          waiting: const Duration(minutes: 9),
        ),
        now,
      );
      expect((cluster.total, cluster.severity), (58, Severity.high));
      final sos = rules.score(
        incident(
          waiting: const Duration(minutes: 4, seconds: 12),
          vulnerable: [VulnerabilityType.seniorCitizen, VulnerabilityType.pwd],
        ),
        now,
      );
      expect((sos.total, sos.severity), (88, Severity.critical));
      final changed = PriorityRules.fromSettings([
        for (final s in defaultPrioritySettings)
          s.key == 'priority.sos' ? s.copyWith(value: 60) : s,
      ]);
      expect(
        changed
            .score(
              incident(
                waiting: const Duration(minutes: 4, seconds: 12),
                vulnerable: [VulnerabilityType.pwd],
              ),
              now,
            )
            .total,
        98,
      );
    });

    test('values are checked like set_setting', () {
      final all = {for (final s in defaultPrioritySettings) s.key: s};
      expect(checkSetting(all, 'priority.sos', 60), isNull);
      expect(
        checkSetting(all, 'priority.waiting_per_minute', 500),
        ActionRejection.invalidValue,
      );
      expect(
        checkSetting(all, 'priority.mock_location', 5),
        ActionRejection.invalidValue,
        reason: 'the penalty cannot become a bonus',
      );
      expect(
        checkSetting(all, 'priority.high_at', 90),
        ActionRejection.invalidValue,
        reason: 'High cannot go above Critical',
      );
      expect(
        checkSetting(all, 'priority.critical_at', 40),
        ActionRejection.invalidValue,
      );
      expect(checkSetting(all, 'priority.nope', 1), ActionRejection.notFound);
    });

    test(
      'the mock: admins change settings, audited; dispatchers cannot',
      () async {
        final backend = MockBackend(clock: () => now, latency: Duration.zero);
        addTearDown(backend.dispose);
        final auth = MockAuthRepository(backend);
        final settings = MockSettingsRepository(backend);
        final seen = <List<AppSetting>>[];
        final sub = settings.watch().listen(seen.add);
        addTearDown(sub.cancel);

        await auth.signIn(
          email: 'dispatcher@sagip.test',
          password: MockSeed.demoPassword,
        );
        await expectLater(
          settings.set('priority.sos', 60),
          throwsA(
            isA<ActionRejected>().having(
              (e) => e.reason,
              'reason',
              ActionRejection.notAllowed,
            ),
          ),
        );
        await auth.signOut();
        await auth.signIn(
          email: 'admin@sagip.test',
          password: MockSeed.demoPassword,
        );
        await settings.set('priority.sos', 60);
        await expectLater(
          settings.set('priority.high_at', 90),
          throwsA(
            isA<ActionRejected>().having(
              (e) => e.reason,
              'reason',
              ActionRejection.invalidValue,
            ),
          ),
        );
        await pumpEventQueue();
        final latest = {for (final s in seen.last) s.key: s};
        expect(latest['priority.sos']!.value, 60);
        expect(latest['priority.sos']!.updatedBy, isNotNull);
        final audit = await MockAuditRepository(backend).watchRecent().first;
        final entry = audit.firstWhere(
          (e) => e.action == AuditAction.settingChanged,
        );
        expect(entry.targetId, 'priority.sos');
        expect(entry.detail, '50 → 60');
      },
    );
  });
}
