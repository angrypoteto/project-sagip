import 'package:flutter_test/flutter_test.dart';
import 'package:sagip_shared/sagip_shared.dart';

Matcher rejected(ActionRejection reason) =>
    throwsA(isA<ActionRejected>().having((e) => e.reason, 'reason', reason));

/// The simulation tools (A3, simulation mode): the same cases as the
/// "simulated incidents" checks in the RLS test.
void main() {
  late MockBackend backend;
  late MockAuthRepository auth;
  late MockSimulationRepository simulation;

  setUp(() async {
    backend = MockBackend(latency: Duration.zero);
    auth = MockAuthRepository(backend);
    simulation = MockSimulationRepository(backend);
    await auth.signIn(
      email: 'admin@sagip.test',
      password: MockSeed.demoPassword,
    );
  });

  tearDown(() => backend.dispose());

  Future<List<Incident>> simulated() async => [
    for (final i in await MockIncidentRepository(backend).watchActive().first)
      if (i.isSimulated) i,
  ];

  test(
    'only an admin, only in simulation mode, only a real barangay',
    () async {
      await expectLater(
        simulation.simulateSos(barangay: 'Barangay 700'),
        rejected(ActionRejection.notAllowed),
      );
      await MockSettingsRepository(backend).set(SettingKeys.simulation, true);
      await expectLater(
        simulation.simulateSos(barangay: 'Nowhere'),
        rejected(ActionRejection.invalidValue),
      );
      await expectLater(
        simulation.simulateCrowdReports(
          barangay: 'Barangay 700',
          type: IncidentType.fire,
          count: 6,
        ),
        rejected(ActionRejection.invalidValue),
      );
      await auth.signOut();
      await auth.signIn(
        email: 'dispatcher@sagip.test',
        password: MockSeed.demoPassword,
      );
      await expectLater(
        simulation.simulateSos(barangay: 'Barangay 700'),
        rejected(ActionRejection.notAllowed),
      );
    },
  );

  test(
    'an SOS and three reports reach the board as simulated, one cluster',
    () async {
      await MockSettingsRepository(backend).set(SettingKeys.simulation, true);
      final now = DateTime.now();
      Future<AnalyticsReport> figures() =>
          MockAnalyticsRepository(backend)
              .report(now.subtract(const Duration(hours: 1)), now.add(_minute));
      final before = await figures();
      final id = await simulation.simulateSos(
        barangay: 'Barangay 700',
        vulnerable: true,
      );
      await simulation.simulateCrowdReports(
        barangay: 'Barangay 700',
        type: IncidentType.fire,
      );

      final board = await simulated();
      final sos = board.singleWhere((i) => i.id == id);
      expect(sos.status, IncidentStatus.pendingVerification);
      expect(sos.vulnerable, [VulnerabilityType.seniorCitizen]);
      expect(sos.residentId, isNull);
      final centre = barangayNamed('Barangay 700')!.center!;
      expect(sos.location.distanceTo(centre), lessThanOrEqualTo(61));

      final cluster = board.singleWhere(
        (i) => i.origin == IncidentOrigin.crowdCluster,
      );
      expect(cluster.crowdReportIds, hasLength(3));
      expect(cluster.type, IncidentType.fire);
      expect(cluster.barangay, 'Barangay 700');

      // Left out of the measurements.
      final after = await figures();
      expect(after.incidents, before.incidents);
      expect(after.sos, before.sos);
      expect(after.delivery.delivered, before.delivery.delivered);

      final audit = await MockAuditRepository(backend).watchRecent().first;
      expect({
        for (final e in audit) e.action,
      }, containsAll([AuditAction.sosSimulated, AuditAction.reportsSimulated]));
    },
  );

  test('a real report joining a simulated cluster makes it real', () {
    final a = Incident(
      id: 'INC-1',
      origin: IncidentOrigin.crowdCluster,
      channel: ReportChannel.app,
      status: IncidentStatus.confirmed,
      location: const GeoPoint(14.57, 120.99),
      barangay: 'Barangay 700',
      district: 'Malate',
      capturedAt: DateTime(2026, 10, 3),
      receivedAt: DateTime(2026, 10, 3),
      isSimulated: true,
    );
    expect(a.copyWith(isSimulated: false).isSimulated, isFalse);
    expect(a.copyWith().isSimulated, isTrue);
    expect(Incident.fromJson(a.toJson()).isSimulated, isTrue);
  });
}

const _minute = Duration(minutes: 1);
